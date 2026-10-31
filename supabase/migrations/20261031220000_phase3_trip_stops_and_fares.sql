-- Phase 3, steps 6-8: normalized route stops, seat legs, fares, and saved routes.
-- Backfills existing routes/fare rows before dropping the mixed legacy fare columns.
begin;

-- Ordered, approved stops used by each published/draft trip.
create table if not exists public.trip_stops (
  id uuid primary key default extensions.gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  stop_order integer not null check (stop_order > 0),
  city_id uuid not null,
  approved_stop_id uuid not null,
  estimated_arrival_at timestamptz,
  estimated_departure_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint trip_stops_trip_order_key unique (trip_id, stop_order),
  constraint trip_stops_id_trip_key unique (id, trip_id),
  constraint trip_stops_approved_stop_city_fkey foreign key (approved_stop_id, city_id)
    references public.approved_stops(id, city_id) on delete restrict,
  constraint trip_stops_city_fkey foreign key (city_id)
    references public.cities(id) on delete restrict
);
create index if not exists trip_stops_city_trip_order_idx on public.trip_stops(city_id, trip_id, stop_order);
create index if not exists trip_stops_approved_stop_fk_idx on public.trip_stops(approved_stop_id);

-- Guard against losing legacy fare data or route stops during normalization.
do $migration_check$
begin
  if exists (
    select 1 from public.trip_segments s
    where s.segment_kind = 'leg'
      and (s.from_city_id is null or s.to_city_id is null
        or s.price_minor is null or s.price_minor <= 0
        or not exists (select 1 from public.approved_stops a where a.city_id=s.from_city_id and a.is_active)
        or not exists (select 1 from public.approved_stops a where a.city_id=s.to_city_id and a.is_active))
  ) then
    raise exception 'Cannot normalize trip segments: a route city has no active approved stop.';
  end if;
  if exists (select 1 from public.trip_segments where segment_kind is null or price_minor is null or price_minor<=0) then
    raise exception 'Cannot normalize trip fares: legacy segments include an unclassified or invalid fare row.';
  end if;
  if exists (
    select 1 from public.booking_segment_allocations a
    join public.trip_segments s on s.id=a.trip_segment_id
    where s.segment_kind <> 'leg'
  ) then
    raise exception 'Cannot normalize fares: a booking allocation points to a non-leg row.';
  end if;
end;
$migration_check$;

-- Reconstruct ordered city stops from the existing physical adjacent legs.
with route_cities as (
  select s.trip_id, s.segment_order as stop_order, s.from_city_id as city_id
  from public.trip_segments s where s.segment_kind='leg'
  union all
  select s.trip_id, s.segment_order + 1, s.to_city_id
  from public.trip_segments s
  where s.segment_kind='leg'
    and not exists (select 1 from public.trip_segments n where n.trip_id=s.trip_id and n.segment_kind='leg' and n.segment_order=s.segment_order+1)
), chosen as (
  select r.trip_id, r.stop_order, r.city_id, a.id approved_stop_id,
         row_number() over (partition by r.trip_id,r.stop_order order by
           case a.stop_kind when 'bus_station' then 1 when 'pickup_dropoff' then 2 else 3 end, a.code) choice
  from route_cities r
  join public.approved_stops a on a.city_id=r.city_id and a.is_active
)
insert into public.trip_stops(trip_id,stop_order,city_id,approved_stop_id)
select trip_id,stop_order,city_id,approved_stop_id from chosen where choice=1
on conflict (trip_id,stop_order) do nothing;

do $migration_check$
begin
  if exists (
    select 1 from public.trip_segments s
    where s.segment_kind='leg'
      and (not exists (select 1 from public.trip_stops a where a.trip_id=s.trip_id and a.stop_order=s.segment_order and a.city_id=s.from_city_id)
        or not exists (select 1 from public.trip_stops b where b.trip_id=s.trip_id and b.stop_order=s.segment_order+1 and b.city_id=s.to_city_id))
  ) then
    raise exception 'Cannot normalize trip segments: route stops are incomplete or out of order.';
  end if;
end;
$migration_check$;

-- Keep each physical segment row ID so existing allocation foreign keys remain valid.
alter table public.trip_segments
  add column from_stop_id uuid,
  add column to_stop_id uuid;
update public.trip_segments s set
  from_stop_id=a.id,
  to_stop_id=b.id
from public.trip_stops a, public.trip_stops b
where s.segment_kind='leg'
  and a.trip_id=s.trip_id and a.stop_order=s.segment_order
  and b.trip_id=s.trip_id and b.stop_order=s.segment_order+1;

create unique index if not exists trip_segments_id_trip_key on public.trip_segments(id,trip_id);
alter table public.trip_segments
  add constraint trip_segments_from_stop_trip_fkey foreign key (from_stop_id,trip_id)
    references public.trip_stops(id,trip_id) on delete cascade,
  add constraint trip_segments_to_stop_trip_fkey foreign key (to_stop_id,trip_id)
    references public.trip_stops(id,trip_id) on delete cascade;

create table if not exists public.trip_fares (
  id uuid primary key default extensions.gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  fare_type text not null check (fare_type in ('segment','override')),
  trip_segment_id uuid,
  from_stop_id uuid not null,
  to_stop_id uuid not null,
  price_minor bigint not null check (price_minor > 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint trip_fares_distinct_stops check (from_stop_id <> to_stop_id),
  constraint trip_fares_trip_segment_fkey foreign key (trip_segment_id,trip_id)
    references public.trip_segments(id,trip_id) on delete cascade,
  constraint trip_fares_from_stop_trip_fkey foreign key (from_stop_id,trip_id)
    references public.trip_stops(id,trip_id) on delete cascade,
  constraint trip_fares_to_stop_trip_fkey foreign key (to_stop_id,trip_id)
    references public.trip_stops(id,trip_id) on delete cascade,
  constraint trip_fares_type_shape check (
    (fare_type='segment' and trip_segment_id is not null)
    or (fare_type='override' and trip_segment_id is null)
  )
);
create unique index if not exists trip_fares_one_price_per_segment_idx
  on public.trip_fares(trip_segment_id) where fare_type='segment';
create unique index if not exists trip_fares_one_override_per_pair_idx
  on public.trip_fares(trip_id,from_stop_id,to_stop_id) where fare_type='override';
create index if not exists trip_fares_trip_pair_idx on public.trip_fares(trip_id,from_stop_id,to_stop_id);

-- Carry forward all leg prices and direct fare overrides in minor currency units.
insert into public.trip_fares(trip_id,fare_type,trip_segment_id,from_stop_id,to_stop_id,price_minor)
select s.trip_id,'segment',s.id,s.from_stop_id,s.to_stop_id,s.price_minor
from public.trip_segments s
where s.segment_kind='leg' and s.price_minor>0
on conflict do nothing;
insert into public.trip_fares(trip_id,fare_type,trip_segment_id,from_stop_id,to_stop_id,price_minor)
select s.trip_id,'override',null,a.id,b.id,s.price_minor
from public.trip_segments s
join public.trip_stops a on a.trip_id=s.trip_id and a.city_id=s.from_city_id
join public.trip_stops b on b.trip_id=s.trip_id and b.city_id=s.to_city_id
where s.segment_kind='fare_override' and s.price_minor>0
on conflict do nothing;

do $migration_check$
begin
  if exists (
    select 1 from public.trip_segments s
    where s.segment_kind='leg' and s.price_minor>0
      and not exists (select 1 from public.trip_fares f where f.trip_segment_id=s.id and f.fare_type='segment')
  ) then raise exception 'Cannot normalize trip fares: one or more segment fares were not copied.'; end if;
  if exists (
    select 1 from public.trip_segments s
    where s.segment_kind='fare_override' and s.price_minor>0
      and not exists (select 1 from public.trip_fares f where f.trip_id=s.trip_id and f.fare_type='override' and f.price_minor=s.price_minor)
  ) then raise exception 'Cannot normalize trip fares: one or more overrides were not copied.'; end if;
end;
$migration_check$;

-- Fare rows are no longer stored in the capacity table.
delete from public.trip_segments where segment_kind='fare_override';

-- Saved routes now persist approved stop endpoints and search preferences.
alter table public.saved_routes
  add column trip_id uuid references public.trips(id) on delete set null,
  add column preferences jsonb not null default '{}'::jsonb
    check (jsonb_typeof(preferences)='object');
alter table public.saved_routes alter column origin_stop_id set not null;
alter table public.saved_routes alter column destination_stop_id set not null;
alter table public.saved_routes drop constraint if exists saved_routes_origin_stop_city_fkey;
alter table public.saved_routes drop constraint if exists saved_routes_destination_stop_city_fkey;
alter table public.saved_routes
  add constraint saved_routes_origin_stop_city_fkey foreign key (origin_stop_id,origin_city_id)
    references public.approved_stops(id,city_id) on delete restrict,
  add constraint saved_routes_destination_stop_city_fkey foreign key (destination_stop_id,destination_city_id)
    references public.approved_stops(id,city_id) on delete restrict,
  add constraint saved_routes_distinct_stops check (origin_stop_id <> destination_stop_id);
create index if not exists saved_routes_trip_fk_idx on public.saved_routes(trip_id);
grant insert (rider_id,origin_city_id,destination_city_id,origin_stop_id,destination_stop_id,label,trip_id,preferences)
  on public.saved_routes to authenticated;
grant update (origin_city_id,destination_city_id,origin_stop_id,destination_stop_id,label,trip_id,preferences)
  on public.saved_routes to authenticated;

create or replace function public.validate_saved_route_trip_link()
returns trigger language plpgsql set search_path=''
as $$
begin
  if new.trip_id is null then return new; end if;
  if not exists (
    select 1 from public.trips t
    where t.id=new.trip_id and t.status='published'
      and t.origin_city_id=new.origin_city_id and t.destination_city_id=new.destination_city_id
      and exists(select 1 from public.trip_stops s where s.trip_id=t.id and s.stop_order=1
        and s.city_id=new.origin_city_id and s.approved_stop_id=new.origin_stop_id)
      and exists(select 1 from public.trip_stops s where s.trip_id=t.id
        and s.city_id=new.destination_city_id and s.approved_stop_id=new.destination_stop_id
        and s.stop_order=(select max(s2.stop_order) from public.trip_stops s2 where s2.trip_id=t.id))
  ) then
    raise exception using errcode='23514',message='Saved trip must match the saved route stops.';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_saved_route_trip_link() from public,anon,authenticated;
create trigger saved_routes_validate_trip_link
  before insert or update of trip_id,origin_city_id,destination_city_id,origin_stop_id,destination_stop_id
  on public.saved_routes for each row execute function public.validate_saved_route_trip_link();

-- Route reads are available only to signed-in users, and only for published trips or their own drafts.
alter table public.trip_stops enable row level security;
alter table public.trip_fares enable row level security;
revoke all on table public.trip_stops, public.trip_fares from public, anon, authenticated;
grant select on table public.trip_stops, public.trip_fares to authenticated;
create policy trip_stops_read_published_or_owned on public.trip_stops for select to authenticated
  using (exists (select 1 from public.trips t where t.id=trip_stops.trip_id and
    (t.status='published' or t.driver_id=(select auth.uid()))));
create policy trip_fares_read_published_or_owned on public.trip_fares for select to authenticated
  using (exists (select 1 from public.trips t where t.id=trip_fares.trip_id and
    (t.status='published' or t.driver_id=(select auth.uid()))));
revoke insert,update,delete on table public.trip_segments, public.trip_stops, public.trip_fares from authenticated;

-- Update the legacy availability helper to use physical legs only.
create or replace function public.available_seats(p_trip_id uuid,p_pickup_order integer,p_dropoff_order integer)
returns integer language sql stable security definer set search_path=''
as $$
  select coalesce(min(greatest(t.total_seats-coalesce(x.occupied,0),0)),0)::integer
  from public.trip_segments s
  join public.trips t on t.id=s.trip_id
  left join lateral (
    select sum(a.seats)::integer occupied
    from public.booking_segment_allocations a
    join public.bookings b on b.id=a.booking_id
    where a.trip_segment_id=s.id and b.status in ('pending','confirmed')
  ) x on true
  where s.trip_id=p_trip_id and s.segment_order between p_pickup_order and p_dropoff_order
$$;
revoke all on function public.available_seats(uuid,integer,integer) from public,anon;
grant execute on function public.available_seats(uuid,integer,integer) to authenticated;

-- The existing RPC contract is retained; route construction now writes approved stops and physical legs.
create or replace function public.create_trip_draft(
  p_vehicle_id uuid,p_city_path uuid[],p_departure_time timestamptz,p_arrival_time timestamptz,
  p_total_seats integer,p_leg_prices_minor bigint[],p_notes text default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid:=auth.uid(); v_trip_id uuid; v_index integer;
  v_city public.cities%rowtype; v_next_city public.cities%rowtype;
  v_from_stop_id uuid; v_to_stop_id uuid;
begin
  if v_user is null or not public.has_role('driver'::public.app_role) then
    raise exception using errcode='42501',message='An approved driver account is required.';
  end if;
  if not exists(select 1 from public.driver_profiles d where d.user_id=v_user and d.status='approved') then
    raise exception using errcode='42501',message='Driver verification is not approved.';
  end if;
  if not exists(select 1 from public.vehicles v where v.id=p_vehicle_id and v.owner_id=v_user and v.status='approved') then
    raise exception using errcode='42501',message='Choose your approved vehicle.';
  end if;
  if p_city_path is null or cardinality(p_city_path)<2 or cardinality(p_city_path)>20
     or p_leg_prices_minor is null or cardinality(p_leg_prices_minor)<>cardinality(p_city_path)-1
     or p_total_seats<1 or p_total_seats>12
     or p_departure_time<=pg_catalog.now() or p_arrival_time<=p_departure_time
     or exists(select 1 from unnest(p_leg_prices_minor) x where x is null or x<=0)
     or exists(select 1 from unnest(p_city_path) as u(id) group by id having count(*)>1)
     or exists(select 1 from unnest(p_city_path) x left join public.cities c on c.id=x where c.id is null or not c.is_active)
     or exists(select 1 from unnest(p_city_path) x where not exists(select 1 from public.approved_stops a where a.city_id=x and a.is_active)) then
    raise exception using errcode='22023',message='Trip route, timing, seat count, or fares are invalid.';
  end if;
  select * into v_city from public.cities where id=p_city_path[1];
  select * into v_next_city from public.cities where id=p_city_path[cardinality(p_city_path)];
  insert into public.trips(driver_id,vehicle_id,origin_city,destination_city,origin_city_id,destination_city_id,
    departure_time,arrival_time,total_seats,notes,status)
  values(v_user,p_vehicle_id,v_city.name_ar,v_next_city.name_ar,v_city.id,v_next_city.id,
    p_departure_time,p_arrival_time,p_total_seats,nullif(pg_catalog.btrim(p_notes),''),'draft')
  returning id into v_trip_id;
  for v_index in 1..cardinality(p_city_path) loop
    select * into v_city from public.cities where id=p_city_path[v_index];
    select a.id into v_from_stop_id from public.approved_stops a where a.city_id=v_city.id and a.is_active
      order by case a.stop_kind when 'bus_station' then 1 when 'pickup_dropoff' then 2 else 3 end,a.code limit 1;
    insert into public.trip_stops(trip_id,stop_order,city_id,approved_stop_id)
      values(v_trip_id,v_index,v_city.id,v_from_stop_id);
  end loop;
  for v_index in 1..cardinality(p_city_path)-1 loop
    select * into v_city from public.cities where id=p_city_path[v_index];
    select * into v_next_city from public.cities where id=p_city_path[v_index+1];
    select id into v_from_stop_id from public.trip_stops where trip_id=v_trip_id and stop_order=v_index;
    select id into v_to_stop_id from public.trip_stops where trip_id=v_trip_id and stop_order=v_index+1;
    insert into public.trip_segments(trip_id,from_stop_id,to_stop_id,segment_order)
      values(v_trip_id,v_from_stop_id,v_to_stop_id,v_index);
    insert into public.trip_fares(trip_id,fare_type,trip_segment_id,from_stop_id,to_stop_id,price_minor)
      select v_trip_id,'segment',s.id,v_from_stop_id,v_to_stop_id,p_leg_prices_minor[v_index]
      from public.trip_segments s where s.trip_id=v_trip_id and s.segment_order=v_index;
  end loop;
  return v_trip_id;
end;
$$;
revoke all on function public.create_trip_draft(uuid,uuid[],timestamptz,timestamptz,integer,bigint[],text) from public,anon,authenticated;
grant execute on function public.create_trip_draft(uuid,uuid[],timestamptz,timestamptz,integer,bigint[],text) to authenticated;

create or replace function public.publish_trip(p_trip_id uuid)
returns public.trips language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_trip public.trips%rowtype;
begin
  if v_user is null then raise exception using errcode='42501',message='Login is required.'; end if;
  select * into v_trip from public.trips where id=p_trip_id for update;
  if not found or v_trip.driver_id<>v_user then raise exception using errcode='42501',message='Trip not found or not owned by you.'; end if;
  if v_trip.status<>'draft' then raise exception using errcode='22023',message='Only a draft trip can be published.'; end if;
  if not exists(select 1 from public.driver_profiles d where d.user_id=v_user and d.status='approved')
     or not exists(select 1 from public.vehicles v where v.id=v_trip.vehicle_id and v.owner_id=v_user and v.status='approved') then
    raise exception using errcode='42501',message='Approved driver verification and vehicle are required.';
  end if;
  if v_trip.departure_time<=pg_catalog.now() or v_trip.arrival_time<=v_trip.departure_time
     or v_trip.origin_city_id is null or v_trip.destination_city_id is null
     or (select count(*) from public.trip_stops where trip_id=p_trip_id)<2
     or (select max(stop_order) from public.trip_stops where trip_id=p_trip_id)<>
        (select count(*) from public.trip_stops where trip_id=p_trip_id)
     or not exists(select 1 from public.trip_segments where trip_id=p_trip_id)
     or exists(select 1 from public.trip_segments s where s.trip_id=p_trip_id and
       (s.from_stop_id is null or s.to_stop_id is null or not exists(select 1 from public.trip_fares f where f.trip_segment_id=s.id and f.fare_type='segment')))
     or exists(select 1 from public.trip_segments s where s.trip_id=p_trip_id
       and s.segment_order<(select max(last_leg.segment_order) from public.trip_segments last_leg where last_leg.trip_id=p_trip_id)
       and not exists(
       select 1 from public.trip_segments n where n.trip_id=s.trip_id and n.segment_order=s.segment_order+1 and n.from_stop_id=s.to_stop_id)) then
    raise exception using errcode='22023',message='Trip route is incomplete or invalid.';
  end if;
  update public.trips set status='published' where id=p_trip_id returning * into v_trip;
  return v_trip;
end;
$$;
revoke all on function public.publish_trip(uuid) from public,anon,authenticated;
grant execute on function public.publish_trip(uuid) to authenticated;

-- Preserve atomic seat reservation while resolving endpoints through the ordered stop list.
create or replace function public.create_booking(p_trip_id uuid,p_pickup_city text,p_dropoff_city text,p_seats_booked integer)
returns public.bookings language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid:=auth.uid(); v_trip public.trips%rowtype; v_pickup public.cities%rowtype; v_dropoff public.cities%rowtype;
  v_pickup_stop_order integer; v_dropoff_stop_order integer; v_pickup_stop_id uuid; v_dropoff_stop_id uuid;
  v_pickup_order integer; v_dropoff_order integer; v_price_minor bigint; v_ttl integer;
  v_booking public.bookings%rowtype; v_occupied integer; v_segment_id uuid;
begin
  if v_user is null or not public.has_role('rider'::public.app_role) then raise exception using errcode='42501',message='Rider login is required.'; end if;
  if p_seats_booked is null or p_seats_booked<1 then raise exception using errcode='22023',message='Seat count must be at least one.'; end if;
  select * into v_trip from public.trips where id=p_trip_id and status='published' for update;
  if not found then raise exception using errcode='P0002',message='Trip is not available.'; end if;
  if v_trip.driver_id=v_user then raise exception using errcode='22023',message='You cannot book your own trip.'; end if;
  select * into v_pickup from public.cities c where c.is_active and
    (c.id::text=p_pickup_city or c.code=p_pickup_city or c.name_ar=p_pickup_city or c.name_en=p_pickup_city) limit 1;
  select * into v_dropoff from public.cities c where c.is_active and
    (c.id::text=p_dropoff_city or c.code=p_dropoff_city or c.name_ar=p_dropoff_city or c.name_en=p_dropoff_city) limit 1;
  if v_pickup.id is null or v_dropoff.id is null or v_pickup.id=v_dropoff.id then
    raise exception using errcode='22023',message='Choose valid, different pickup and drop-off cities.';
  end if;
  select stop_order,id into v_pickup_stop_order,v_pickup_stop_id from public.trip_stops
    where trip_id=p_trip_id and city_id=v_pickup.id;
  select stop_order,id into v_dropoff_stop_order,v_dropoff_stop_id from public.trip_stops
    where trip_id=p_trip_id and city_id=v_dropoff.id;
  if v_pickup_stop_order is null or v_dropoff_stop_order is null or v_pickup_stop_order>=v_dropoff_stop_order then
    raise exception using errcode='22023',message='Pickup and drop-off must follow the trip route.';
  end if;
  v_pickup_order:=v_pickup_stop_order;
  v_dropoff_order:=v_dropoff_stop_order-1;
  select f.price_minor into v_price_minor from public.trip_fares f
    where f.trip_id=p_trip_id and f.fare_type='override'
      and f.from_stop_id=v_pickup_stop_id and f.to_stop_id=v_dropoff_stop_id;
  if v_price_minor is null then
    select coalesce(sum(f.price_minor),0) into v_price_minor
    from public.trip_segments s join public.trip_fares f on f.trip_segment_id=s.id and f.fare_type='segment'
    where s.trip_id=p_trip_id and s.segment_order between v_pickup_order and v_dropoff_order;
  end if;
  if v_price_minor<=0 then raise exception using errcode='22023',message='No valid fare is configured for this route.'; end if;
  for v_segment_id in select s.id from public.trip_segments s where s.trip_id=p_trip_id
    and s.segment_order between v_pickup_order and v_dropoff_order order by s.segment_order
  loop
    select coalesce(sum(a.seats),0)::integer into v_occupied from public.booking_segment_allocations a
      join public.bookings b on b.id=a.booking_id where a.trip_segment_id=v_segment_id and b.status in ('pending','confirmed');
    if v_occupied+p_seats_booked>v_trip.total_seats then
      raise exception using errcode='P0001',message='Not enough seats remain on this part of the route.';
    end if;
  end loop;
  select (value#>>'{}')::integer into v_ttl from public.app_settings where key='booking_pending_ttl_minutes';
  v_ttl:=coalesce(v_ttl,15);
  insert into public.bookings(trip_id,passenger_id,pickup_city,dropoff_city,pickup_city_id,dropoff_city_id,
    pickup_order,dropoff_order,seats_booked,total_price,total_price_minor,status,expires_at)
  values(p_trip_id,v_user,v_pickup.name_ar,v_dropoff.name_ar,v_pickup.id,v_dropoff.id,
    v_pickup_order,v_dropoff_order,p_seats_booked,(v_price_minor::numeric/100)*p_seats_booked,
    v_price_minor*p_seats_booked,'pending',pg_catalog.now()+pg_catalog.make_interval(mins=>v_ttl))
  returning * into v_booking;
  insert into public.booking_segment_allocations(booking_id,trip_segment_id,seats)
  select v_booking.id,s.id,p_seats_booked from public.trip_segments s
  where s.trip_id=p_trip_id and s.segment_order between v_pickup_order and v_dropoff_order;
  return v_booking;
end;
$$;
revoke all on function public.create_booking(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.create_booking(uuid,text,text,integer) to authenticated;

create or replace function public.search_trips(
  p_origin_city_id uuid,p_destination_city_id uuid,p_from timestamptz,p_to timestamptz,p_seats integer default 1
) returns table(trip_id uuid,driver_id uuid,origin_city_id uuid,destination_city_id uuid,
  departure_time timestamptz,arrival_time timestamptz,seats_available integer,price_minor bigint)
language sql stable security definer set search_path=''
as $$
  with matches as (
    select t.id,t.driver_id,t.origin_city_id,t.destination_city_id,t.departure_time,t.arrival_time,t.total_seats,
      min(p.stop_order) pickup_stop_order,min(d.stop_order) dropoff_stop_order
    from public.trips t
    join public.trip_stops p on p.trip_id=t.id and p.city_id=p_origin_city_id
    join public.trip_stops d on d.trip_id=t.id and d.city_id=p_destination_city_id and d.stop_order>p.stop_order
    where auth.uid() is not null and t.status='published'
      and t.departure_time>=p_from and t.departure_time<p_to
      and p_seats between 1 and t.total_seats and p_origin_city_id<>p_destination_city_id
    group by t.id,t.driver_id,t.origin_city_id,t.destination_city_id,t.departure_time,t.arrival_time,t.total_seats
  ), requested_legs as (
    select m.*,s.id segment_id,s.segment_order
    from matches m join public.trip_segments s on s.trip_id=m.id
      and s.segment_order between m.pickup_stop_order and m.dropoff_stop_order-1
  ), occupancy as (
    select l.*,l.total_seats-coalesce((select sum(a.seats)::integer
      from public.booking_segment_allocations a join public.bookings b on b.id=a.booking_id
      where a.trip_segment_id=l.segment_id and b.status in ('pending','confirmed')),0) remaining
    from requested_legs l
  ), totals as (
    select id trip_id,driver_id,origin_city_id,destination_city_id,departure_time,arrival_time,
      min(remaining)::integer seats_available,
      (select sum(f.price_minor)::bigint from public.trip_fares f
        join public.trip_segments s on s.id=f.trip_segment_id
        where f.trip_id=o.id and f.fare_type='segment'
          and s.segment_order between o.pickup_stop_order and o.dropoff_stop_order-1) base_price
    from occupancy o
    group by id,driver_id,origin_city_id,destination_city_id,departure_time,arrival_time,pickup_stop_order,dropoff_stop_order
  )
  select x.trip_id,x.driver_id,x.origin_city_id,x.destination_city_id,x.departure_time,x.arrival_time,x.seats_available,
    coalesce((select f.price_minor from public.trip_fares f
      join public.trip_stops p on p.id=f.from_stop_id join public.trip_stops d on d.id=f.to_stop_id
      where f.trip_id=x.trip_id and f.fare_type='override'
        and p.city_id=p_origin_city_id and d.city_id=p_destination_city_id),x.base_price)
  from totals x where x.seats_available>=p_seats and x.base_price>0
  order by x.departure_time
$$;
revoke all on function public.search_trips(uuid,uuid,timestamptz,timestamptz,integer) from public,anon;
grant execute on function public.search_trips(uuid,uuid,timestamptz,timestamptz,integer) to authenticated;

-- Remove legacy city and fare columns after all reads/writes have been moved.
drop index if exists public.trip_segments_unique_adjacent_leg;
drop index if exists public.trip_segments_unique_pair_fare;
drop index if exists public.trip_segments_city_pair_idx;
drop index if exists public.trip_segments_from_city_fk_idx;
drop index if exists public.trip_segments_to_city_fk_idx;
alter table public.trip_segments drop constraint if exists trip_segments_price_minor_nonnegative;
create unique index if not exists trip_segments_trip_order_key on public.trip_segments(trip_id,segment_order);
alter table public.trip_segments
  alter column from_stop_id set not null,
  alter column to_stop_id set not null,
  drop column from_city,
  drop column to_city,
  drop column from_city_id,
  drop column to_city_id,
  drop column price,
  drop column price_minor,
  drop column segment_kind;

-- No database client can set schedule rows or fares directly; workflow RPCs own those writes.
revoke insert,update,delete on table public.trip_stops,public.trip_fares from authenticated;

commit;
