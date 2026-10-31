-- Phase 4b: guarded workflow transitions and atomic trip / booking operations.
begin;

alter table public.trips
  add column if not exists cancelled_by uuid references public.profiles(id) on delete set null,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text;
update public.trips set cancelled_at=coalesce(cancelled_at,updated_at),
  cancellation_reason=coalesce(cancellation_reason,'legacy_cancelled')
where status='cancelled' and (cancelled_at is null or cancellation_reason is null);
alter table public.trips add constraint trips_cancellation_metadata_check
  check ((status='cancelled' and cancelled_at is not null and cancellation_reason is not null)
      or (status<>'cancelled' and cancelled_at is null and cancellation_reason is null)) not valid;

revoke all on table public.allowed_status_transitions from public, anon, authenticated;
create unique index if not exists allowed_status_transitions_actor_idx
  on public.allowed_status_transitions(entity_type,from_status,to_status,actor_role)
  where actor_role is not null;
create unique index if not exists allowed_status_transitions_system_idx
  on public.allowed_status_transitions(entity_type,from_status,to_status)
  where actor_role is null;

create or replace function public.enforce_workflow_transition()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if old.status is distinct from new.status and not exists (
    select 1 from public.allowed_status_transitions a
    where a.entity_type=TG_ARGV[0]
      and a.from_status=old.status::text
      and a.to_status=new.status::text
  ) then
    raise exception using errcode='22023',
      message=pg_catalog.format('Invalid %s status transition: %s -> %s',TG_ARGV[0],old.status::text,new.status::text);
  end if;
  return new;
end;
$$;
revoke all on function public.enforce_workflow_transition() from public, anon, authenticated;

create or replace function public.log_workflow_transition()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if old.status is distinct from new.status then
    insert into public.audit_log(actor_id,action,entity_type,entity_id,occurred_at,metadata)
    values(auth.uid(),'status_transition',TG_ARGV[0],new.id,pg_catalog.now(),
      pg_catalog.jsonb_build_object('from',old.status::text,'to',new.status::text));
  end if;
  return new;
end;
$$;
revoke all on function public.log_workflow_transition() from public, anon, authenticated;
create trigger trips_workflow_guard before update of status on public.trips
for each row execute function public.enforce_workflow_transition('trip');
create trigger bookings_workflow_guard before update of status on public.bookings
for each row execute function public.enforce_workflow_transition('booking');
create trigger trips_workflow_audit after update of status on public.trips
for each row execute function public.log_workflow_transition('trip');
create trigger bookings_workflow_audit after update of status on public.bookings
for each row execute function public.log_workflow_transition('booking');

create or replace function public.create_trip_draft(
  p_vehicle_id uuid,
  p_city_path uuid[],
  p_departure_time timestamptz,
  p_arrival_time timestamptz,
  p_total_seats integer,
  p_leg_prices_minor bigint[],
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid();
  v_trip_id uuid;
  v_index integer;
  v_city public.cities%rowtype;
  v_next_city public.cities%rowtype;
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
     or p_departure_time<=pg_catalog.now()
     or p_arrival_time<=p_departure_time
     or exists(select 1 from unnest(p_leg_prices_minor) x where x is null or x<0)
     or exists(select 1 from (select unnest(p_city_path) id) q group by id having count(*)>1) then
    raise exception using errcode='22023',message='Trip route, timing, seat count, or fares are invalid.';
  end if;
  if exists(select 1 from unnest(p_city_path) x left join public.cities c on c.id=x where c.id is null or not c.is_active) then
    raise exception using errcode='22023',message='Trip route contains an unknown or inactive city.';
  end if;
  select * into v_city from public.cities where id=p_city_path[1];
  select * into v_next_city from public.cities where id=p_city_path[cardinality(p_city_path)];
  insert into public.trips(driver_id,vehicle_id,origin_city,destination_city,origin_city_id,destination_city_id,
    departure_time,arrival_time,total_seats,notes,status)
  values(v_user,p_vehicle_id,v_city.name_ar,v_next_city.name_ar,v_city.id,v_next_city.id,
    p_departure_time,p_arrival_time,p_total_seats,nullif(pg_catalog.btrim(p_notes),''),'draft')
  returning id into v_trip_id;

  for v_index in 1..cardinality(p_city_path)-1 loop
    select * into v_city from public.cities where id=p_city_path[v_index];
    select * into v_next_city from public.cities where id=p_city_path[v_index+1];
    insert into public.trip_segments(trip_id,from_city,to_city,from_city_id,to_city_id,segment_order,segment_kind,price,price_minor)
    values(v_trip_id,v_city.name_ar,v_next_city.name_ar,v_city.id,v_next_city.id,v_index,'leg',
      p_leg_prices_minor[v_index]::numeric/100,p_leg_prices_minor[v_index]);
  end loop;
  return v_trip_id;
end;
$$;
revoke all on function public.create_trip_draft(uuid,uuid[],timestamptz,timestamptz,integer,bigint[],text) from public,anon,authenticated;
grant execute on function public.create_trip_draft(uuid,uuid[],timestamptz,timestamptz,integer,bigint[],text) to authenticated;

create or replace function public.publish_trip(p_trip_id uuid)
returns public.trips
language plpgsql
security definer
set search_path=''
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
     or not exists(select 1 from public.trip_segments s where s.trip_id=p_trip_id and s.segment_kind='leg')
     or exists(select 1 from public.trip_segments s where s.trip_id=p_trip_id and s.segment_kind='leg' and (s.price_minor is null or s.from_city_id is null or s.to_city_id is null))
     or exists(select 1 from public.trip_segments a join public.trip_segments b on b.trip_id=a.trip_id and b.segment_kind='leg' and b.segment_order=a.segment_order+1 where a.trip_id=p_trip_id and a.segment_kind='leg' and a.to_city_id<>b.from_city_id) then
    raise exception using errcode='22023',message='Trip route is incomplete or invalid.';
  end if;
  update public.trips set status='published' where id=p_trip_id returning * into v_trip;
  return v_trip;
end;
$$;
revoke all on function public.publish_trip(uuid) from public,anon,authenticated;
grant execute on function public.publish_trip(uuid) to authenticated;

create or replace function public.create_booking(p_trip_id uuid,p_pickup_city text,p_dropoff_city text,p_seats_booked integer)
returns public.bookings
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user uuid:=auth.uid(); v_trip public.trips%rowtype; v_pickup public.cities%rowtype; v_dropoff public.cities%rowtype;
  v_pickup_order integer; v_dropoff_order integer; v_price_minor bigint; v_ttl integer;
  v_booking public.bookings%rowtype; v_capacity integer; v_occupied integer; v_segment_id uuid;
begin
  if v_user is null or not public.has_role('rider'::public.app_role) then raise exception using errcode='42501',message='Rider login is required.'; end if;
  if p_seats_booked is null or p_seats_booked<1 then raise exception using errcode='22023',message='Seat count must be at least one.'; end if;
  select * into v_trip from public.trips where id=p_trip_id and status='published' for update;
  if not found then raise exception using errcode='P0002',message='Trip is not available.'; end if;
  if v_trip.driver_id=v_user then raise exception using errcode='22023',message='You cannot book your own trip.'; end if;
  select * into v_pickup from public.cities c where c.is_active and (c.id::text=p_pickup_city or c.code=p_pickup_city or c.name_ar=p_pickup_city or c.name_en=p_pickup_city) limit 1;
  select * into v_dropoff from public.cities c where c.is_active and (c.id::text=p_dropoff_city or c.code=p_dropoff_city or c.name_ar=p_dropoff_city or c.name_en=p_dropoff_city) limit 1;
  if v_pickup.id is null or v_dropoff.id is null or v_pickup.id=v_dropoff.id then raise exception using errcode='22023',message='Choose valid, different pickup and drop-off cities.'; end if;

  select s.segment_order into v_pickup_order from public.trip_segments s
    where s.trip_id=p_trip_id and s.segment_kind='leg' and s.from_city_id=v_pickup.id;
  select s.segment_order into v_dropoff_order from public.trip_segments s
    where s.trip_id=p_trip_id and s.segment_kind='leg' and s.to_city_id=v_dropoff.id;
  if v_pickup_order is null or v_dropoff_order is null or v_pickup_order>v_dropoff_order then
    raise exception using errcode='22023',message='Pickup and drop-off must follow the trip route.';
  end if;
  if exists(select 1 from public.trip_segments a join public.trip_segments b on b.trip_id=a.trip_id and b.segment_kind='leg' and b.segment_order=a.segment_order+1 where a.trip_id=p_trip_id and a.segment_kind='leg' and a.segment_order between v_pickup_order and v_dropoff_order-1 and a.to_city_id<>b.from_city_id) then
    raise exception using errcode='22023',message='Trip route legs do not connect.';
  end if;
  select coalesce(max(s.price_minor),0) into v_price_minor from public.trip_segments s
    where s.trip_id=p_trip_id and s.segment_kind='fare_override' and s.from_city_id=v_pickup.id and s.to_city_id=v_dropoff.id;
  if v_price_minor=0 then
    select coalesce(sum(s.price_minor),0) into v_price_minor from public.trip_segments s
      where s.trip_id=p_trip_id and s.segment_kind='leg' and s.segment_order between v_pickup_order and v_dropoff_order;
  end if;
  if v_price_minor<=0 then raise exception using errcode='22023',message='No valid fare is configured for this route.'; end if;

  for v_segment_id in select s.id from public.trip_segments s where s.trip_id=p_trip_id and s.segment_kind='leg'
    and s.segment_order between v_pickup_order and v_dropoff_order order by s.segment_order
  loop
    select coalesce(sum(a.seats),0)::integer into v_occupied from public.booking_segment_allocations a
      join public.bookings b on b.id=a.booking_id
      where a.trip_segment_id=v_segment_id and b.status in ('pending','confirmed');
    if v_occupied+p_seats_booked>v_trip.total_seats then raise exception using errcode='P0001',message='Not enough seats remain on this part of the route.'; end if;
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
  select v_booking.id,s.id,p_seats_booked from public.trip_segments s where s.trip_id=p_trip_id
    and s.segment_kind='leg' and s.segment_order between v_pickup_order and v_dropoff_order;
  return v_booking;
end;
$$;
revoke all on function public.create_booking(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.create_booking(uuid,text,text,integer) to authenticated;

create or replace function public.driver_respond_booking(p_booking_id uuid,p_accept boolean,p_reason text default null)
returns public.bookings
language plpgsql
security definer
set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype;
begin
  if v_user is null then raise exception using errcode='42501',message='Login is required.'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found then raise exception using errcode='P0002',message='Booking not found.'; end if;
  select * into v_trip from public.trips where id=v_booking.trip_id for update;
  if v_trip.driver_id<>v_user then raise exception using errcode='42501',message='Only the trip driver can respond.'; end if;
  if not public.has_role('driver'::public.app_role) or v_booking.status<>'pending' then raise exception using errcode='22023',message='Booking is no longer awaiting a driver response.'; end if;
  if v_booking.expires_at<=pg_catalog.now() then
    update public.bookings set status='cancelled',cancelled_by=null,cancelled_at=pg_catalog.now(),cancellation_reason='request_expired',status_reason='Driver response window elapsed',response_at=pg_catalog.now()
      where id=p_booking_id returning * into v_booking;
    return v_booking;
  end if;
  if p_accept then
    update public.bookings set status='confirmed',expires_at=null,response_at=pg_catalog.now(),status_reason=null where id=p_booking_id returning * into v_booking;
  else
    update public.bookings set status='rejected',expires_at=null,response_at=pg_catalog.now(),status_reason=nullif(pg_catalog.btrim(p_reason),'') where id=p_booking_id returning * into v_booking;
  end if;
  return v_booking;
end;
$$;
revoke all on function public.driver_respond_booking(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.driver_respond_booking(uuid,boolean,text) to authenticated;

create or replace function public.cancel_booking(p_booking_id uuid,p_reason text default null)
returns public.bookings
language plpgsql
security definer
set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype;
begin
  if v_user is null then raise exception using errcode='42501',message='Login is required.'; end if;
  select * into v_booking from public.bookings where id=p_booking_id for update;
  if not found or v_booking.passenger_id<>v_user then raise exception using errcode='42501',message='Booking not found or not owned by you.'; end if;
  select * into v_trip from public.trips where id=v_booking.trip_id;
  if v_booking.status not in ('pending','confirmed') or v_trip.departure_time<=pg_catalog.now() then raise exception using errcode='22023',message='This booking can no longer be cancelled.'; end if;
  update public.bookings set status='cancelled',cancelled_by=v_user,cancelled_at=pg_catalog.now(),
    cancellation_reason='rider_request',status_reason=nullif(pg_catalog.btrim(p_reason),'')
    where id=p_booking_id returning * into v_booking;
  return v_booking;
end;
$$;
revoke all on function public.cancel_booking(uuid,text) from public,anon,authenticated;
grant execute on function public.cancel_booking(uuid,text) to authenticated;

create or replace function public.cancel_trip(p_trip_id uuid,p_reason text default null)
returns public.trips
language plpgsql
security definer
set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_trip public.trips%rowtype;
begin
  if v_user is null then raise exception using errcode='42501',message='Login is required.'; end if;
  select * into v_trip from public.trips where id=p_trip_id for update;
  if not found or v_trip.driver_id<>v_user or not public.has_role('driver'::public.app_role) then raise exception using errcode='42501',message='Trip not found or not owned by you.'; end if;
  if v_trip.status not in ('draft','published','in_progress') then raise exception using errcode='22023',message='Trip cannot be cancelled in its current state.'; end if;
  update public.trips set status='cancelled',cancelled_by=v_user,cancelled_at=pg_catalog.now(),
    cancellation_reason='driver_request' where id=p_trip_id returning * into v_trip;
  update public.bookings set status='cancelled',cancelled_by=v_user,cancelled_at=pg_catalog.now(),
    cancellation_reason='trip_cancelled',status_reason=nullif(pg_catalog.btrim(p_reason),'')
    where trip_id=p_trip_id and status in ('pending','confirmed');
  return v_trip;
end;
$$;
revoke all on function public.cancel_trip(uuid,text) from public,anon,authenticated;
grant execute on function public.cancel_trip(uuid,text) to authenticated;

create or replace function public.expire_pending_bookings()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_count integer;
begin
  update public.bookings set status='cancelled',cancelled_by=null,cancelled_at=pg_catalog.now(),
    cancellation_reason='request_expired',status_reason='Driver response window elapsed'
    where status='pending' and expires_at<=pg_catalog.now();
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function public.expire_pending_bookings() from public,anon,authenticated;
grant execute on function public.expire_pending_bookings() to postgres;

create or replace function public.search_trips(
 p_origin_city_id uuid,p_destination_city_id uuid,p_from timestamptz,p_to timestamptz,p_seats integer default 1
)
returns table(trip_id uuid,driver_id uuid,origin_city_id uuid,destination_city_id uuid,departure_time timestamptz,arrival_time timestamptz,seats_available integer,price_minor bigint)
language sql
stable
security definer
set search_path=''
as $$
 with matches as (
  select t.id,t.driver_id,t.origin_city_id,t.destination_city_id,t.departure_time,t.arrival_time,t.total_seats,
    min(l.segment_order) pickup_order,min(r.segment_order) dropoff_order
  from public.trips t
  join public.trip_segments l on l.trip_id=t.id and l.segment_kind='leg' and l.from_city_id=p_origin_city_id
  join public.trip_segments r on r.trip_id=t.id and r.segment_kind='leg' and r.to_city_id=p_destination_city_id and r.segment_order>=l.segment_order
  where auth.uid() is not null and t.status='published' and t.departure_time>=p_from and t.departure_time<p_to
    and p_seats between 1 and t.total_seats and p_origin_city_id<>p_destination_city_id
  group by t.id,t.driver_id,t.origin_city_id,t.destination_city_id,t.departure_time,t.arrival_time,t.total_seats
 ), legs as (
  select m.*,s.id segment_id,s.segment_order,s.price_minor
  from matches m join public.trip_segments s on s.trip_id=m.id and s.segment_kind='leg'
   and s.segment_order between m.pickup_order and m.dropoff_order
 ), capacity as (
  select l.*,l.total_seats-coalesce((
   select sum(a.seats)::integer from public.booking_segment_allocations a
    join public.bookings b on b.id=a.booking_id
    where a.trip_segment_id=l.segment_id and b.status in ('pending','confirmed')
  ),0) remaining
  from legs l
 ), aggregated as (
  select id trip_id,driver_id,origin_city_id,destination_city_id,departure_time,arrival_time,
    min(remaining)::integer seats_available,sum(price_minor)::bigint price_minor
  from capacity group by id,driver_id,origin_city_id,destination_city_id,departure_time,arrival_time
 )
 select a.trip_id,a.driver_id,a.origin_city_id,a.destination_city_id,a.departure_time,a.arrival_time,a.seats_available,
  coalesce((select f.price_minor from public.trip_segments f where f.trip_id=a.trip_id and f.segment_kind='fare_override'
    and f.from_city_id=p_origin_city_id and f.to_city_id=p_destination_city_id limit 1),a.price_minor)
 from aggregated a where a.seats_available>=p_seats order by a.departure_time;
$$;
revoke all on function public.search_trips(uuid,uuid,timestamptz,timestamptz,integer) from public,anon;
grant execute on function public.search_trips(uuid,uuid,timestamptz,timestamptz,integer) to authenticated;

create extension if not exists pg_cron;
do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='expire-pending-bookings-every-minute';
  if v_job is not null then perform cron.unschedule(v_job); end if;
  perform cron.schedule('expire-pending-bookings-every-minute','* * * * *','select public.expire_pending_bookings();');
end;
$$;

commit;
