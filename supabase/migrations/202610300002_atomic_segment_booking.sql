-- Phase 1, Step 3: explicit fare rows and atomic segment-aware booking.
-- Existing trip_segments rows are intentionally left unclassified (NULL).
-- Classify legacy rows as 'leg' or 'fare_override' after reviewing their data.

begin;

alter table public.trip_segments
  add column if not exists segment_kind text;

alter table public.trip_segments
  drop constraint if exists trip_segments_segment_kind_check;
alter table public.trip_segments
  add constraint trip_segments_segment_kind_check
  check (segment_kind in ('leg', 'fare_override'));

comment on column public.trip_segments.segment_kind is
  'leg rows connect adjacent stops; fare_override rows price an exact city pair and never represent occupancy legs. NULL means legacy/unclassified and blocks booking.';
comment on column public.trip_segments.segment_order is
  'For leg rows, stop order of the from_city; it connects stop N to stop N+1. Fare override order is informational only.';

create unique index if not exists trip_segments_unique_adjacent_leg
  on public.trip_segments (trip_id, segment_order)
  where segment_kind = 'leg';
create unique index if not exists trip_segments_unique_pair_fare
  on public.trip_segments (trip_id, from_city, to_city)
  where segment_kind = 'fare_override';

create or replace function public.available_seats(
  p_trip_id uuid,
  p_pickup_order integer,
  p_dropoff_order integer
) returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select greatest(
    0,
    coalesce(t.total_seats, 0) - coalesce((
      select max(coalesce(occupied.seats, 0))
      from public.trip_segments leg
      left join lateral (
        select sum(b.seats_booked)::integer as seats
        from public.bookings b
        where b.trip_id = leg.trip_id
          and b.status in ('pending', 'confirmed')
          and exists (
            select 1 from public.trip_segments pickup_leg
            where pickup_leg.trip_id = leg.trip_id
              and pickup_leg.segment_kind = 'leg'
              and pickup_leg.from_city = b.pickup_city
              and pickup_leg.segment_order <= leg.segment_order
          )
          and exists (
            select 1 from public.trip_segments dropoff_leg
            where dropoff_leg.trip_id = leg.trip_id
              and dropoff_leg.segment_kind = 'leg'
              and dropoff_leg.to_city = b.dropoff_city
              and dropoff_leg.segment_order >= leg.segment_order
          )
      ) occupied on true
      where leg.trip_id = t.id
        and leg.segment_kind = 'leg'
        and leg.segment_order >= p_pickup_order
        and leg.segment_order < p_dropoff_order
    ), 0)
  )
  from public.trips t
  where t.id = p_trip_id;
$$;

revoke all on function public.available_seats(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.available_seats(uuid, integer, integer)
  to authenticated;

create or replace function public.create_booking(
  p_trip_id uuid,
  p_pickup_city text,
  p_dropoff_city text,
  p_seats_booked integer
) returns public.bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_passenger_id uuid := auth.uid();
  v_trip public.trips%rowtype;
  v_pickup_order integer;
  v_dropoff_order integer;
  v_leg_count integer;
  v_route_origin text;
  v_route_destination text;
  v_price numeric(10,2);
  v_booking public.bookings%rowtype;
  v_leg record;
  v_occupied integer;
begin
  if v_passenger_id is null then
    raise exception using errcode = '42501', message = 'Login is required to book a trip.';
  end if;
  if p_seats_booked is null or p_seats_booked < 1 then
    raise exception using errcode = '22023', message = 'Seat count must be at least one.';
  end if;
  if p_pickup_city is null or p_dropoff_city is null or p_pickup_city = p_dropoff_city then
    raise exception using errcode = '22023', message = 'Choose different pickup and drop-off stops.';
  end if;

  select t.* into v_trip
  from public.trips t
  where t.id = p_trip_id and t.status = 'upcoming'
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'This trip is no longer available.';
  end if;

  if exists (
    select 1 from public.trip_segments s
    where s.trip_id = p_trip_id and s.segment_kind is null
  ) then
    raise exception using errcode = '22023',
      message = 'Trip segments need explicit leg/fare classification before booking.';
  end if;

  select count(*)::integer, min(s.segment_order), max(s.segment_order)
  into v_leg_count, v_pickup_order, v_dropoff_order
  from public.trip_segments s
  where s.trip_id = p_trip_id and s.segment_kind = 'leg';

  if v_leg_count = 0 or v_pickup_order <> 1 or v_dropoff_order <> v_leg_count then
    raise exception using errcode = '22023',
      message = 'Trip adjacent legs must have contiguous stop order starting at one.';
  end if;
  if exists (
    select 1
    from public.trip_segments current_leg
    join public.trip_segments next_leg
      on next_leg.trip_id = current_leg.trip_id
     and next_leg.segment_kind = 'leg'
     and next_leg.segment_order = current_leg.segment_order + 1
    where current_leg.trip_id = p_trip_id
      and current_leg.segment_kind = 'leg'
      and current_leg.to_city <> next_leg.from_city
  ) then
    raise exception using errcode = '22023',
      message = 'Trip adjacent legs do not form one connected stop chain.';
  end if;
  if exists (
    select 1
    from (
      select s.from_city as city
      from public.trip_segments s
      where s.trip_id = p_trip_id and s.segment_kind = 'leg'
      union all
      select s.to_city
      from public.trip_segments s
      where s.trip_id = p_trip_id and s.segment_kind = 'leg'
        and s.segment_order = v_leg_count
    ) route_stops
    group by route_stops.city
    having count(*) > 1
  ) then
    raise exception using errcode = '22023',
      message = 'Trip stop city names must be unique to identify booking stops.';
  end if;
  if exists (
    select 1 from public.trip_segments s
    where s.trip_id = p_trip_id and s.segment_kind = 'leg'
      and s.segment_order < 1
  ) then
    raise exception using errcode = '22023', message = 'Invalid adjacent leg order.';
  end if;

  select s.segment_order into v_pickup_order
  from public.trip_segments s
  where s.trip_id = p_trip_id and s.segment_kind = 'leg'
    and s.from_city = p_pickup_city;
  if not found then
    select s.segment_order + 1 into v_pickup_order
    from public.trip_segments s
    where s.trip_id = p_trip_id and s.segment_kind = 'leg'
      and s.to_city = p_pickup_city;
  end if;

  select s.segment_order + 1 into v_dropoff_order
  from public.trip_segments s
  where s.trip_id = p_trip_id and s.segment_kind = 'leg'
    and s.to_city = p_dropoff_city;
  if not found then
    select s.segment_order into v_dropoff_order
    from public.trip_segments s
    where s.trip_id = p_trip_id and s.segment_kind = 'leg'
      and s.from_city = p_dropoff_city;
  end if;

  if v_pickup_order is null or v_dropoff_order is null
     or v_pickup_order >= v_dropoff_order then
    raise exception using errcode = '22023',
      message = 'Pickup and drop-off must be valid stops in route order.';
  end if;

  select s.from_city into v_route_origin
  from public.trip_segments s
  where s.trip_id = p_trip_id and s.segment_kind = 'leg'
  order by s.segment_order limit 1;
  select s.to_city into v_route_destination
  from public.trip_segments s
  where s.trip_id = p_trip_id and s.segment_kind = 'leg'
  order by s.segment_order desc limit 1;

  if v_route_origin is distinct from v_trip.origin_city
     or v_route_destination is distinct from v_trip.destination_city
     or not exists (
       select 1 from public.trip_segments s
       where s.trip_id = p_trip_id and s.segment_kind = 'leg'
         and s.segment_order = v_pickup_order and s.from_city = p_pickup_city
     ) and v_pickup_order <> 1
     or not exists (
       select 1 from public.trip_segments s
       where s.trip_id = p_trip_id and s.segment_kind = 'leg'
         and s.segment_order = v_dropoff_order - 1 and s.to_city = p_dropoff_city
     ) then
    raise exception using errcode = '22023', message = 'Trip stop chain is inconsistent.';
  end if;

  select f.price into v_price
  from public.trip_segments f
  where f.trip_id = p_trip_id and f.segment_kind = 'fare_override'
    and f.from_city = p_pickup_city and f.to_city = p_dropoff_city;

  if v_price is null then
    select sum(l.price)::numeric(10,2) into v_price
    from public.trip_segments l
    where l.trip_id = p_trip_id and l.segment_kind = 'leg'
      and l.segment_order >= v_pickup_order
      and l.segment_order < v_dropoff_order;
  end if;
  if v_price is null then
    raise exception using errcode = '22023', message = 'No fare is configured for this route.';
  end if;

  for v_leg in
    select l.segment_order
    from public.trip_segments l
    where l.trip_id = p_trip_id and l.segment_kind = 'leg'
      and l.segment_order >= v_pickup_order
      and l.segment_order < v_dropoff_order
    order by l.segment_order
  loop
    select coalesce(sum(b.seats_booked), 0)::integer into v_occupied
    from public.bookings b
    where b.trip_id = p_trip_id
      and b.status in ('pending', 'confirmed')
      and exists (
        select 1 from public.trip_segments pickup_leg
        where pickup_leg.trip_id = p_trip_id
          and pickup_leg.segment_kind = 'leg'
          and pickup_leg.from_city = b.pickup_city
          and pickup_leg.segment_order <= v_leg.segment_order
      )
      and exists (
        select 1 from public.trip_segments dropoff_leg
        where dropoff_leg.trip_id = p_trip_id
          and dropoff_leg.segment_kind = 'leg'
          and dropoff_leg.to_city = b.dropoff_city
          and dropoff_leg.segment_order >= v_leg.segment_order
      );

    if v_occupied + p_seats_booked > v_trip.total_seats then
      raise exception using errcode = 'P0001', message = 'Not enough seats remain for this route.';
    end if;
  end loop;

  insert into public.bookings (
    trip_id, passenger_id, pickup_city, dropoff_city,
    pickup_order, dropoff_order, seats_booked, total_price, status
  ) values (
    p_trip_id, v_passenger_id, p_pickup_city, p_dropoff_city,
    v_pickup_order, v_dropoff_order, p_seats_booked,
    v_price * p_seats_booked, 'pending'
  ) returning * into v_booking;

  return v_booking;
end;
$$;

revoke all on function public.create_booking(uuid, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.create_booking(uuid, text, text, integer)
  to authenticated;

comment on function public.create_booking(uuid, text, text, integer) is
  'Atomically creates an authenticated passenger booking. SECURITY DEFINER is required because direct client INSERT is revoked and the function must read all overlapping bookings despite RLS. It derives passenger_id from auth.uid(), locks the trip, computes fare server-side, and reserves only adjacent legs.';

commit;
