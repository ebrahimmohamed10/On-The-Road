-- Phase 5: live trip operations, boarding, emergency contacts, and expiring share links.
begin;

create table if not exists public.trip_location_updates (
  id uuid primary key default extensions.gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  driver_id uuid not null references public.profiles(id) on delete cascade,
  location extensions.geography(point,4326) not null,
  recorded_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists trip_location_updates_trip_time_idx on public.trip_location_updates(trip_id,recorded_at desc);
create index if not exists trip_location_updates_location_gist_idx on public.trip_location_updates using gist(location);
create index if not exists trip_location_updates_driver_idx on public.trip_location_updates(driver_id);

create table if not exists public.trip_events (
  id uuid primary key default extensions.gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  event_type text not null check (event_type in ('trip_started','trip_completed','trip_cancelled','boarding_confirmed','passenger_no_show','safety_incident')),
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists trip_events_trip_time_idx on public.trip_events(trip_id,occurred_at desc);
create index if not exists trip_events_actor_idx on public.trip_events(actor_id);

create table if not exists public.boarding_events (
  id uuid primary key default extensions.gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  trip_id uuid not null references public.trips(id) on delete cascade,
  passenger_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null check (event_type in ('boarded','alighted','no_show')),
  recorded_by uuid not null references public.profiles(id) on delete restrict,
  occurred_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint boarding_events_booking_type_key unique(booking_id,event_type)
);
create index if not exists boarding_events_trip_time_idx on public.boarding_events(trip_id,occurred_at);
create index if not exists boarding_events_passenger_idx on public.boarding_events(passenger_id);

create table if not exists public.emergency_contacts (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  display_name text not null check (length(btrim(display_name)) between 1 and 100),
  phone_e164 text not null check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  relationship text,
  is_default boolean not null default false,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint emergency_contacts_user_phone_key unique(user_id,phone_e164)
);
create unique index if not exists emergency_contacts_one_default_idx on public.emergency_contacts(user_id) where is_default;
create index if not exists emergency_contacts_user_idx on public.emergency_contacts(user_id);

create table if not exists public.trip_shares (
  id uuid primary key default extensions.gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  trip_id uuid not null references public.trips(id) on delete cascade,
  rider_id uuid not null references public.profiles(id) on delete cascade,
  emergency_contact_id uuid references public.emergency_contacts(id) on delete set null,
  token_hash bytea not null unique,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists trip_shares_rider_created_idx on public.trip_shares(rider_id,created_at desc);
create index if not exists trip_shares_trip_idx on public.trip_shares(trip_id);

create table if not exists public.emergency_incidents (
  id uuid primary key default extensions.gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete restrict,
  booking_id uuid references public.bookings(id) on delete set null,
  reporter_id uuid not null references public.profiles(id) on delete restrict,
  incident_type text not null check (incident_type in ('safety_concern','medical','vehicle_breakdown','other')),
  details text,
  location extensions.geography(point,4326),
  status text not null default 'open' check (status in ('open','acknowledged','resolved')),
  reported_at timestamptz not null default pg_catalog.now(),
  resolved_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint emergency_incidents_resolution_check check ((status='resolved')=(resolved_at is not null))
);
create index if not exists emergency_incidents_trip_reported_idx on public.emergency_incidents(trip_id,reported_at desc);
create index if not exists emergency_incidents_reporter_idx on public.emergency_incidents(reporter_id);
create index if not exists emergency_incidents_location_gist_idx on public.emergency_incidents using gist(location);
create index if not exists trip_shares_emergency_contact_idx on public.trip_shares(emergency_contact_id);

do $$ declare t text; begin
 foreach t in array array['trip_location_updates','trip_events','boarding_events','emergency_contacts','trip_shares','emergency_incidents'] loop
  execute pg_catalog.format('alter table public.%I enable row level security',t);
  execute pg_catalog.format('revoke all on table public.%I from public,anon,authenticated',t);
  execute pg_catalog.format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t);
 end loop;
end $$;

grant select,insert,update,delete on public.emergency_contacts to authenticated;
create policy emergency_contacts_own_read on public.emergency_contacts for select to authenticated using(user_id=(select auth.uid()));
create policy emergency_contacts_own_insert on public.emergency_contacts for insert to authenticated with check(user_id=(select auth.uid()));
create policy emergency_contacts_own_update on public.emergency_contacts for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
create policy emergency_contacts_own_delete on public.emergency_contacts for delete to authenticated using(user_id=(select auth.uid()));

grant select on public.trip_events,public.boarding_events,public.emergency_incidents to authenticated;
create policy trip_events_participant_read on public.trip_events for select to authenticated using (
 exists(select 1 from public.trips t where t.id=trip_id and (t.driver_id=(select auth.uid()) or exists(select 1 from public.bookings b where b.trip_id=t.id and b.passenger_id=(select auth.uid()))))
);
create policy boarding_events_participant_read on public.boarding_events for select to authenticated using (
 passenger_id=(select auth.uid()) or exists(select 1 from public.trips t where t.id=trip_id and t.driver_id=(select auth.uid()))
);
create policy emergency_incidents_participant_read on public.emergency_incidents for select to authenticated using (
 reporter_id=(select auth.uid()) or exists(select 1 from public.trips t where t.id=trip_id and t.driver_id=(select auth.uid()))
 or exists(select 1 from public.bookings b where b.trip_id=trip_id and b.passenger_id=(select auth.uid()))
 or public.has_role('admin'::public.app_role)
);
-- Location rows are only readable by the dedicated bounded RPC.
revoke all on table public.trip_location_updates,public.trip_shares from public,anon,authenticated;

create or replace function public.start_trip(p_trip_id uuid)
returns public.trips
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_trip public.trips%rowtype;
begin
 if v_user is null then raise exception using errcode='42501',message='Login required.'; end if;
 select * into v_trip from public.trips where id=p_trip_id for update;
 if not found or v_trip.driver_id<>v_user or not public.has_role('driver'::public.app_role) then raise exception using errcode='42501',message='Trip not found or not owned by you.'; end if;
 if v_trip.status<>'published' or v_trip.departure_time>pg_catalog.now()+interval '60 minutes' then raise exception using errcode='22023',message='Trip is not ready to start.'; end if;
 update public.trips set status='in_progress' where id=p_trip_id returning * into v_trip;
 insert into public.trip_events(trip_id,actor_id,event_type) values(p_trip_id,v_user,'trip_started');
 return v_trip;
end $$;
revoke all on function public.start_trip(uuid) from public,anon,authenticated;
grant execute on function public.start_trip(uuid) to authenticated;

create or replace function public.record_trip_location(p_trip_id uuid,p_latitude double precision,p_longitude double precision)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_id uuid;
begin
 if v_user is null or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then raise exception using errcode='22023',message='Valid coordinates and login are required.'; end if;
 if not exists(select 1 from public.trips where id=p_trip_id and driver_id=v_user and status='in_progress') then raise exception using errcode='42501',message='Only the driver can share location during an active trip.'; end if;
 if exists(select 1 from public.trip_location_updates where trip_id=p_trip_id and recorded_at>pg_catalog.now()-interval '4 seconds') then
   raise exception using errcode='22023',message='Location updates are limited to one every five seconds.';
 end if;
 insert into public.trip_location_updates(trip_id,driver_id,location)
 values(p_trip_id,v_user,extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326)::extensions.geography)
 returning id into v_id;
 return v_id;
end $$;
revoke all on function public.record_trip_location(uuid,double precision,double precision) from public,anon;
grant execute on function public.record_trip_location(uuid,double precision,double precision) to authenticated;

create or replace function public.get_active_trip_location(p_trip_id uuid)
returns table(latitude double precision,longitude double precision,recorded_at timestamptz)
language sql stable security definer set search_path=''
as $$
 select extensions.st_y(l.location::extensions.geometry),extensions.st_x(l.location::extensions.geometry),l.recorded_at
 from public.trip_location_updates l join public.trips t on t.id=l.trip_id
 where l.trip_id=p_trip_id and t.status='in_progress' and auth.uid() is not null
  and (t.driver_id=auth.uid() or exists(select 1 from public.bookings b where b.trip_id=t.id and b.passenger_id=auth.uid() and b.status='confirmed'))
 order by l.recorded_at desc limit 1
$$;
revoke all on function public.get_active_trip_location(uuid) from public,anon;
grant execute on function public.get_active_trip_location(uuid) to authenticated;

create or replace function public.confirm_boarding(p_booking_id uuid)
returns public.boarding_events
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_event public.boarding_events%rowtype;
begin
 if v_user is null then raise exception using errcode='42501',message='Login required.'; end if;
 select * into v_booking from public.bookings where id=p_booking_id for update;
 if not found or v_booking.status<>'confirmed' then raise exception using errcode='22023',message='Booking is not confirmed.'; end if;
 select * into v_trip from public.trips where id=v_booking.trip_id;
 if v_trip.driver_id<>v_user or v_trip.status<>'in_progress' then raise exception using errcode='42501',message='Only the driver can confirm boarding on an active trip.'; end if;
 insert into public.boarding_events(booking_id,trip_id,passenger_id,event_type,recorded_by)
 values(v_booking.id,v_booking.trip_id,v_booking.passenger_id,'boarded',v_user)
 returning * into v_event;
 insert into public.trip_events(trip_id,actor_id,event_type,details)
 values(v_trip.id,v_user,'boarding_confirmed',pg_catalog.jsonb_build_object('booking_id',v_booking.id));
 return v_event;
end $$;
revoke all on function public.confirm_boarding(uuid) from public,anon,authenticated;
grant execute on function public.confirm_boarding(uuid) to authenticated;

create or replace function public.complete_trip(p_trip_id uuid)
returns public.trips
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_trip public.trips%rowtype; v_grace integer;
begin
 if v_user is null then raise exception using errcode='42501',message='Login required.'; end if;
 select * into v_trip from public.trips where id=p_trip_id for update;
 if not found or v_trip.driver_id<>v_user or not public.has_role('driver'::public.app_role) then raise exception using errcode='42501',message='Trip not found or not owned by you.'; end if;
 select (value#>>'{}')::integer into v_grace from public.app_settings where key='trip_completion_grace_minutes';
 if v_trip.status<>'in_progress' or (v_trip.arrival_time is not null and pg_catalog.now()<v_trip.arrival_time+pg_catalog.make_interval(mins=>coalesce(v_grace,10))) then
   raise exception using errcode='22023',message='Trip has not reached its completion time.';
 end if;
 insert into public.boarding_events(booking_id,trip_id,passenger_id,event_type,recorded_by)
 select b.id,b.trip_id,b.passenger_id,
  case when exists(select 1 from public.boarding_events be where be.booking_id=b.id and be.event_type='boarded') then 'alighted' else 'no_show' end,
  v_user
 from public.bookings b where b.trip_id=p_trip_id and b.status='confirmed'
 on conflict(booking_id,event_type) do nothing;
 update public.bookings b set
  status=case when exists(select 1 from public.boarding_events be where be.booking_id=b.id and be.event_type='boarded') then 'completed'::public.booking_status else 'no_show'::public.booking_status end
 where b.trip_id=p_trip_id and b.status='confirmed';
 update public.trips set status='completed' where id=p_trip_id returning * into v_trip;
 insert into public.trip_events(trip_id,actor_id,event_type) values(p_trip_id,v_user,'trip_completed');
 return v_trip;
end $$;
revoke all on function public.complete_trip(uuid) from public,anon,authenticated;
grant execute on function public.complete_trip(uuid) to authenticated;

create or replace function public.create_trip_share(p_booking_id uuid,p_emergency_contact_id uuid default null)
returns text
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_token text;
begin
 if v_user is null then raise exception using errcode='42501',message='Login required.'; end if;
 select * into v_booking from public.bookings where id=p_booking_id and passenger_id=v_user for update;
 if not found or v_booking.status<>'confirmed' then raise exception using errcode='42501',message='Only your confirmed trip can be shared.'; end if;
 select * into v_trip from public.trips where id=v_booking.trip_id;
 if v_trip.status not in ('published','in_progress') then raise exception using errcode='22023',message='Trip is not shareable now.'; end if;
 if p_emergency_contact_id is not null and not exists(select 1 from public.emergency_contacts where id=p_emergency_contact_id and user_id=v_user) then raise exception using errcode='42501',message='Emergency contact not found.'; end if;
 v_token:=pg_catalog.encode(extensions.gen_random_bytes(32),'hex');
 insert into public.trip_shares(booking_id,trip_id,rider_id,emergency_contact_id,token_hash,expires_at)
 values(v_booking.id,v_trip.id,v_user,p_emergency_contact_id,extensions.digest(v_token,'sha256'),
   least(coalesce(v_trip.arrival_time,pg_catalog.now()+interval '24 hours')+interval '24 hours',pg_catalog.now()+interval '7 days'));
 return v_token;
end $$;
revoke all on function public.create_trip_share(uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_trip_share(uuid,uuid) to authenticated;

create or replace function public.revoke_trip_share(p_share_id uuid)
returns boolean
language plpgsql security definer set search_path=''
as $$
begin
 update public.trip_shares set revoked_at=pg_catalog.now()
 where id=p_share_id and rider_id=auth.uid() and revoked_at is null;
 return found;
end $$;
revoke all on function public.revoke_trip_share(uuid) from public,anon,authenticated;
grant execute on function public.revoke_trip_share(uuid) to authenticated;

create or replace function public.get_shared_trip_status(p_token text)
returns table(trip_status public.trip_status,origin_city text,destination_city text,departure_time timestamptz,driver_name text,driver_avatar_path text,latitude double precision,longitude double precision,location_recorded_at timestamptz,expires_at timestamptz)
language sql stable security definer set search_path=''
as $$
 select t.status,t.origin_city,t.destination_city,t.departure_time,p.name,p.avatar_path,
   case when t.status='in_progress' then extensions.st_y(l.location::extensions.geometry) end,
   case when t.status='in_progress' then extensions.st_x(l.location::extensions.geometry) end,
   case when t.status='in_progress' then l.recorded_at end,s.expires_at
 from public.trip_shares s
 join public.trips t on t.id=s.trip_id
 join public.profiles p on p.id=t.driver_id
 left join lateral(select * from public.trip_location_updates x where x.trip_id=t.id order by x.recorded_at desc limit 1) l on true
 where s.token_hash=extensions.digest(p_token,'sha256') and s.revoked_at is null and s.expires_at>pg_catalog.now()
$$;
revoke all on function public.get_shared_trip_status(text) from public,authenticated;
grant execute on function public.get_shared_trip_status(text) to anon;

create or replace function public.report_emergency(
 p_booking_id uuid,p_incident_type text,p_details text default null,p_latitude double precision default null,p_longitude double precision default null
)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_id uuid;
begin
 if v_user is null or p_incident_type not in ('safety_concern','medical','vehicle_breakdown','other')
   or (p_latitude is null)<>(p_longitude is null)
   or (p_latitude is not null and (p_latitude not between -90 and 90 or p_longitude not between -180 and 180))
 then raise exception using errcode='22023',message='Valid incident details and login are required.'; end if;
 select * into v_booking from public.bookings where id=p_booking_id and passenger_id=v_user and status in ('confirmed','completed','no_show');
 if not found then
  select b.* into v_booking from public.bookings b join public.trips t on t.id=b.trip_id
  where b.id=p_booking_id and t.driver_id=v_user and b.status in ('confirmed','completed','no_show');
 end if;
 if not found then raise exception using errcode='42501',message='A booking for this trip is required.'; end if;
 select * into v_trip from public.trips where id=v_booking.trip_id;
 insert into public.emergency_incidents(trip_id,booking_id,reporter_id,incident_type,details,location)
 values(v_trip.id,v_booking.id,v_user,p_incident_type,nullif(pg_catalog.btrim(p_details),''),
  case when p_latitude is null then null else extensions.st_setsrid(extensions.st_makepoint(p_longitude,p_latitude),4326)::extensions.geography end)
 returning id into v_id;
 insert into public.trip_events(trip_id,actor_id,event_type,details)
 values(v_trip.id,v_user,'safety_incident',pg_catalog.jsonb_build_object('incident_id',v_id,'incident_type',p_incident_type));
 return v_id;
end $$;
revoke all on function public.report_emergency(uuid,text,text,double precision,double precision) from public,anon,authenticated;
grant execute on function public.report_emergency(uuid,text,text,double precision,double precision) to authenticated;

create or replace function public.purge_expired_trip_locations()
returns integer
language plpgsql security definer set search_path=''
as $$
declare v_days integer; v_deleted integer;
begin
 select (value#>>'{}')::integer into v_days from public.app_settings where key='location_retention_days';
 delete from public.trip_location_updates where recorded_at<pg_catalog.now()-pg_catalog.make_interval(days=>coalesce(v_days,30));
 get diagnostics v_deleted=row_count;
 return v_deleted;
end $$;
revoke all on function public.purge_expired_trip_locations() from public,anon,authenticated;
grant execute on function public.purge_expired_trip_locations() to postgres;

do $$ declare v_job bigint; begin
 select jobid into v_job from cron.job where jobname='purge-trip-locations-daily';
 if v_job is not null then perform cron.unschedule(v_job); end if;
 perform cron.schedule('purge-trip-locations-daily','20 3 * * *','select public.purge_expired_trip_locations();');
end $$;

commit;
