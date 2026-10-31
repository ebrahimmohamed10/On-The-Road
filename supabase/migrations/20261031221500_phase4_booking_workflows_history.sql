-- Phase 4, steps 9-11: booking stops/history, expiry state, and cancellation workflows.
begin;

-- Store the exact approved pickup and drop-off stops chosen from the trip route.
alter table public.bookings
  add column pickup_stop_id uuid,
  add column dropoff_stop_id uuid;

update public.bookings b set
  pickup_stop_id=(select s.id from public.trip_stops s where s.trip_id=b.trip_id and s.city_id=b.pickup_city_id order by s.stop_order limit 1),
  dropoff_stop_id=(select s.id from public.trip_stops s where s.trip_id=b.trip_id and s.city_id=b.dropoff_city_id order by s.stop_order limit 1);

do $booking_backfill_check$
begin
  if exists(select 1 from public.bookings where pickup_stop_id is null or dropoff_stop_id is null) then
    raise exception 'Could not map every existing booking endpoint to a trip stop; review legacy bookings before continuing.';
  end if;
end;
$booking_backfill_check$;

alter table public.bookings
  alter column pickup_stop_id set not null,
  alter column dropoff_stop_id set not null,
  add constraint bookings_pickup_stop_trip_fkey foreign key (pickup_stop_id,trip_id)
    references public.trip_stops(id,trip_id) on delete restrict,
  add constraint bookings_dropoff_stop_trip_fkey foreign key (dropoff_stop_id,trip_id)
    references public.trip_stops(id,trip_id) on delete restrict,
  add constraint bookings_distinct_stops check (pickup_stop_id <> dropoff_stop_id) not valid;
alter table public.bookings validate constraint bookings_distinct_stops;

-- Every pending request must have a deadline. Older rows receive the configured default window.
update public.bookings b set expires_at=b.created_at + pg_catalog.make_interval(mins=>15)
where b.status='pending' and b.expires_at is null;
alter table public.bookings
  add constraint bookings_pending_expires_check check (status <> 'pending' or expires_at is not null) not valid;
alter table public.bookings validate constraint bookings_pending_expires_check;
create index if not exists bookings_pending_expiration_idx on public.bookings(expires_at) where status='pending';
create index if not exists bookings_pickup_stop_fk_idx on public.bookings(pickup_stop_id);
create index if not exists bookings_dropoff_stop_fk_idx on public.bookings(dropoff_stop_id);

-- Preserve a queryable status timeline in addition to the general audit log.
create table public.booking_status_history (
  id uuid primary key default extensions.gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  old_status public.booking_status,
  new_status public.booking_status not null,
  changed_by uuid references public.profiles(id) on delete set null,
  change_reason text,
  created_at timestamptz not null default pg_catalog.now(),
  constraint booking_status_history_change_check check (old_status is null or old_status <> new_status)
);
create index booking_status_history_booking_created_idx
  on public.booking_status_history(booking_id,created_at desc);
alter table public.booking_status_history enable row level security;
revoke all on table public.booking_status_history from public,anon,authenticated;
grant select on table public.booking_status_history to authenticated;
create policy booking_status_history_participant_read on public.booking_status_history
for select to authenticated using (
  exists (
    select 1 from public.bookings b join public.trips t on t.id=b.trip_id
    where b.id=booking_status_history.booking_id
      and ((select auth.uid())=b.passenger_id or (select auth.uid())=t.driver_id
        or public.has_role('admin'::public.app_role))
  )
);

create or replace function public.capture_booking_status_history()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='INSERT' then
    insert into public.booking_status_history(booking_id,old_status,new_status,changed_by,change_reason,created_at)
    values(new.id,null,new.status,auth.uid(),coalesce(nullif(pg_catalog.btrim(new.status_reason),''),'booking_created'),new.created_at);
    return new;
  end if;
  if old.status is distinct from new.status then
    insert into public.booking_status_history(booking_id,old_status,new_status,changed_by,change_reason)
    values(new.id,old.status,new.status,auth.uid(),
      coalesce(nullif(pg_catalog.btrim(new.status_reason),''),nullif(pg_catalog.btrim(new.cancellation_reason),'')));
  end if;
  return new;
end;
$$;
revoke all on function public.capture_booking_status_history() from public,anon,authenticated;
create trigger booking_status_history_capture after insert or update on public.bookings
for each row execute function public.capture_booking_status_history();

-- Seed a clearly marked baseline record only if older booking rows exist.
insert into public.booking_status_history(booking_id,old_status,new_status,changed_by,change_reason,created_at)
select b.id,null,b.status,null,'baseline_state_before_history_tracking',b.created_at
from public.bookings b
where not exists(select 1 from public.booking_status_history h where h.booking_id=b.id);

-- Expiration is a distinct terminal state; refunds can follow a cancellation later.
insert into public.allowed_status_transitions(entity_type,from_status,to_status,actor_role)
select v.entity_type,v.from_status,v.to_status,v.actor_role::public.app_role
from (values
  ('booking','pending','expired',null),
  ('booking','cancelled','refunded',null)
) v(entity_type,from_status,to_status,actor_role)
where not exists (
  select 1 from public.allowed_status_transitions a
  where a.entity_type=v.entity_type and a.from_status=v.from_status
    and a.to_status=v.to_status and a.actor_role is not distinct from v.actor_role::public.app_role
);

-- Atomic booking creation retains the existing RPC contract and segment-level capacity locks.
create or replace function public.create_booking(p_trip_id uuid,p_pickup_city text,p_dropoff_city text,p_seats_booked integer)
returns public.bookings language plpgsql security definer set search_path=''
as $$
declare
  v_user uuid:=auth.uid(); v_trip public.trips%rowtype; v_pickup public.cities%rowtype; v_dropoff public.cities%rowtype;
  v_pickup_stop_order integer; v_dropoff_stop_order integer; v_pickup_stop_id uuid; v_dropoff_stop_id uuid;
  v_pickup_order integer; v_dropoff_order integer; v_price_minor bigint; v_ttl integer;
  v_booking public.bookings%rowtype; v_occupied integer; v_segment_id uuid;
begin
  if v_user is null or not public.has_role('rider'::public.app_role) then
    raise exception using errcode='42501',message='Rider login is required.';
  end if;
  if p_seats_booked is null or p_seats_booked<1 then
    raise exception using errcode='22023',message='Seat count must be at least one.';
  end if;
  select * into v_trip from public.trips where id=p_trip_id and status='published' for update;
  if not found then raise exception using errcode='P0002',message='Trip is not available.'; end if;
  if v_trip.departure_time<=pg_catalog.now() then
    raise exception using errcode='22023',message='This trip has already departed.';
  end if;
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
      join public.bookings b on b.id=a.booking_id
      where a.trip_segment_id=v_segment_id and b.status in ('pending','confirmed');
    if v_occupied+p_seats_booked>v_trip.total_seats then
      raise exception using errcode='P0001',message='Not enough seats remain on this part of the route.';
    end if;
  end loop;
  select (value#>>'{}')::integer into v_ttl from public.app_settings where key='booking_pending_ttl_minutes';
  v_ttl:=coalesce(v_ttl,15);
  if v_ttl<1 or v_ttl>1440 then raise exception using errcode='22023',message='Booking response window setting is invalid.'; end if;
  insert into public.bookings(trip_id,passenger_id,pickup_city,dropoff_city,pickup_city_id,dropoff_city_id,
    pickup_stop_id,dropoff_stop_id,pickup_order,dropoff_order,seats_booked,total_price,total_price_minor,status,expires_at)
  values(p_trip_id,v_user,v_pickup.name_ar,v_dropoff.name_ar,v_pickup.id,v_dropoff.id,
    v_pickup_stop_id,v_dropoff_stop_id,v_pickup_order,v_dropoff_order,p_seats_booked,
    (v_price_minor::numeric/100)*p_seats_booked,v_price_minor*p_seats_booked,'pending',
    pg_catalog.now()+pg_catalog.make_interval(mins=>v_ttl))
  returning * into v_booking;
  insert into public.booking_segment_allocations(booking_id,trip_segment_id,seats)
  select v_booking.id,s.id,p_seats_booked from public.trip_segments s
  where s.trip_id=p_trip_id and s.segment_order between v_pickup_order and v_dropoff_order;
  return v_booking;
end;
$$;
revoke all on function public.create_booking(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.create_booking(uuid,text,text,integer) to authenticated;

-- Do not accept a late driver response after the same expiration deadline used by the cron worker.
create or replace function public.driver_respond_booking(p_booking_id uuid,p_accept boolean,p_reason text default null)
returns public.bookings language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype;
begin
  if v_user is null then raise exception using errcode='42501',message='Login is required.'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found then raise exception using errcode='P0002',message='Booking not found.'; end if;
  select * into v_trip from public.trips where id=v_booking.trip_id for update;
  if v_trip.driver_id<>v_user then raise exception using errcode='42501',message='Only the trip driver can respond.'; end if;
  if not public.has_role('driver'::public.app_role) or v_booking.status<>'pending' then
    raise exception using errcode='22023',message='Booking is no longer awaiting a driver response.';
  end if;
  if v_booking.expires_at<=pg_catalog.now() then
    update public.bookings set status='expired',status_reason='Driver response window elapsed',response_at=null
      where id=p_booking_id returning * into v_booking;
    return v_booking;
  end if;
  if p_accept then
    update public.bookings set status='confirmed',expires_at=null,response_at=pg_catalog.now(),status_reason=null
      where id=p_booking_id returning * into v_booking;
  else
    update public.bookings set status='rejected',expires_at=null,response_at=pg_catalog.now(),
      status_reason=nullif(pg_catalog.btrim(p_reason),'') where id=p_booking_id returning * into v_booking;
  end if;
  return v_booking;
end;
$$;
revoke all on function public.driver_respond_booking(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.driver_respond_booking(uuid,boolean,text) to authenticated;

-- Expiration does not mean cancellation or refund; the seat becomes available because capacity queries count only pending/confirmed.
create or replace function public.expire_pending_bookings()
returns integer language plpgsql security definer set search_path=''
as $$
declare v_count integer;
begin
  update public.bookings set status='expired',status_reason='Driver response window elapsed'
  where status='pending' and expires_at<=pg_catalog.now();
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.expire_pending_bookings() from public,anon,authenticated;
grant execute on function public.expire_pending_bookings() to postgres;

-- Revoke the pending deadline when a rider or driver cancels the booking/trip.
create or replace function public.cancel_booking(p_booking_id uuid,p_reason text default null)
returns public.bookings language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype;
begin
  if v_user is null then raise exception using errcode='42501',message='Login is required.'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.passenger_id<>v_user then
    raise exception using errcode='42501',message='Booking not found or not owned by you.';
  end if;
  select * into v_trip from public.trips where id=v_booking.trip_id;
  if v_booking.status not in ('pending','confirmed') or v_trip.departure_time<=pg_catalog.now() then
    raise exception using errcode='22023',message='This booking can no longer be cancelled.';
  end if;
  update public.bookings set status='cancelled',cancelled_by=v_user,cancelled_at=pg_catalog.now(),
    cancellation_reason='rider_request',status_reason=nullif(pg_catalog.btrim(p_reason),''),expires_at=null
  where id=p_booking_id returning * into v_booking;
  return v_booking;
end;
$$;
revoke all on function public.cancel_booking(uuid,text) from public,anon,authenticated;
grant execute on function public.cancel_booking(uuid,text) to authenticated;

create or replace function public.cancel_trip(p_trip_id uuid,p_reason text default null)
returns public.trips language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_trip public.trips%rowtype;
begin
  if v_user is null then raise exception using errcode='42501',message='Login is required.'; end if;
  select * into v_trip from public.trips where id=p_trip_id for update;
  if not found or v_trip.driver_id<>v_user or not public.has_role('driver'::public.app_role) then
    raise exception using errcode='42501',message='Trip not found or not owned by you.';
  end if;
  if v_trip.status not in ('draft','published','in_progress') then
    raise exception using errcode='22023',message='Trip cannot be cancelled in its current state.';
  end if;
  update public.trips set status='cancelled',cancelled_by=v_user,cancelled_at=pg_catalog.now(),
    cancellation_reason='driver_request' where id=p_trip_id returning * into v_trip;
  update public.bookings set status='cancelled',cancelled_by=v_user,cancelled_at=pg_catalog.now(),
    cancellation_reason='trip_cancelled',status_reason=nullif(pg_catalog.btrim(p_reason),''),expires_at=null
  where trip_id=p_trip_id and status in ('pending','confirmed');
  return v_trip;
end;
$$;
revoke all on function public.cancel_trip(uuid,text) from public,anon,authenticated;
grant execute on function public.cancel_trip(uuid,text) to authenticated;

commit;
