-- Phase 4a: typed trip/booking states, minor-unit pricing, capacity allocations, and application settings.
begin;

do $$ begin
  create type public.trip_status as enum ('draft','published','in_progress','completed','cancelled');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.booking_status as enum ('pending','confirmed','rejected','cancelled','completed','no_show');
exception when duplicate_object then null; end $$;

-- Policies are removed before changing status column types because PostgreSQL
-- stores their expressions against the original text type.
drop policy if exists trips_insert_as_approved_driver on public.trips;
drop policy if exists trips_update_as_approved_driver on public.trips;
drop policy if exists trips_read_open_or_owned on public.trips;
drop policy if exists trip_segments_read_authenticated on public.trip_segments;
drop policy if exists bookings_cancel_own on public.bookings;
drop index if exists public.trips_route_time_idx;

alter table public.trips drop constraint if exists trips_status_check;
alter table public.trips alter column status drop default;
alter table public.trips alter column status type public.trip_status
  using (case status when 'upcoming' then 'published' when 'active' then 'in_progress' else status end)::public.trip_status;
alter table public.trips alter column status set default 'draft'::public.trip_status;
alter table public.trips alter column status set not null;

alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings alter column status drop default;
alter table public.bookings alter column status type public.booking_status using status::public.booking_status;
alter table public.bookings alter column status set default 'pending'::public.booking_status;
alter table public.bookings alter column status set not null;

alter table public.trips
  add column if not exists vehicle_id uuid references public.vehicles(id) on delete restrict,
  add constraint trips_total_seats_positive check (total_seats > 0) not valid,
  add constraint trips_route_cities_distinct check (origin_city_id is null or destination_city_id is null or origin_city_id <> destination_city_id) not valid;
alter table public.trip_segments
  add column if not exists price_minor bigint,
  add constraint trip_segments_price_minor_nonnegative check (price_minor is null or price_minor >= 0) not valid;
update public.trip_segments set price_minor=round(price*100)::bigint where price_minor is null;
alter table public.trip_segments alter column price_minor set not null;

alter table public.bookings
  add column if not exists pickup_city_id uuid references public.cities(id) on delete restrict,
  add column if not exists dropoff_city_id uuid references public.cities(id) on delete restrict,
  add column if not exists total_price_minor bigint,
  add column if not exists expires_at timestamptz,
  add column if not exists cancelled_by uuid references public.profiles(id) on delete set null,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists response_at timestamptz,
  add column if not exists status_reason text,
  add constraint bookings_total_price_minor_nonnegative check (total_price_minor is null or total_price_minor >= 0) not valid,
  add constraint bookings_cancellation_metadata_check check (
    (status = 'cancelled' and cancelled_at is not null and cancellation_reason is not null)
    or (status <> 'cancelled' and cancelled_at is null and cancellation_reason is null)
  ) not valid;
update public.bookings b set
  pickup_city_id=coalesce(b.pickup_city_id,c1.id),
  dropoff_city_id=coalesce(b.dropoff_city_id,c2.id),
  total_price_minor=coalesce(b.total_price_minor,round(b.total_price*100)::bigint),
  expires_at=case when b.status='pending' then coalesce(b.expires_at,b.created_at+interval '15 minutes') else b.expires_at end,
  cancelled_at=case when b.status='cancelled' then coalesce(b.cancelled_at,b.updated_at) else b.cancelled_at end,
  cancellation_reason=case when b.status='cancelled' then coalesce(b.cancellation_reason,'legacy_cancelled') else b.cancellation_reason end
from public.cities c1, public.cities c2
where c1.name_ar=b.pickup_city and c2.name_ar=b.dropoff_city;
update public.bookings b set
  total_price_minor=coalesce(total_price_minor,round(total_price*100)::bigint),
  expires_at=case when status='pending' then coalesce(expires_at,created_at+interval '15 minutes') else expires_at end,
  cancelled_at=case when status='cancelled' then coalesce(cancelled_at,updated_at) else cancelled_at end,
  cancellation_reason=case when status='cancelled' then coalesce(cancellation_reason,'legacy_cancelled') else cancellation_reason end
where total_price_minor is null or (status='pending' and expires_at is null) or (status='cancelled' and (cancelled_at is null or cancellation_reason is null));
alter table public.bookings alter column total_price_minor set not null;

create index if not exists bookings_status_expiry_idx on public.bookings(status, expires_at) where status='pending';
create index if not exists bookings_trip_status_idx on public.bookings(trip_id,status);
create index if not exists bookings_pickup_city_fk_idx on public.bookings(pickup_city_id);
create index if not exists bookings_dropoff_city_fk_idx on public.bookings(dropoff_city_id);
create index if not exists trips_vehicle_id_idx on public.trips(vehicle_id);
create index if not exists trips_route_time_idx
  on public.trips(origin_city_id,destination_city_id,departure_time)
  where status in ('published'::public.trip_status,'in_progress'::public.trip_status);

create table if not exists public.booking_segment_allocations (
  id uuid primary key default extensions.gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  trip_segment_id uuid not null references public.trip_segments(id) on delete restrict,
  seats integer not null check (seats > 0),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint booking_segment_allocations_booking_leg_key unique (booking_id, trip_segment_id)
);
create index if not exists booking_segment_allocations_segment_idx
  on public.booking_segment_allocations(trip_segment_id, booking_id);

create table if not exists public.app_settings (
  key text primary key check (key ~ '^[a-z][a-z0-9_.]+$'),
  value jsonb not null,
  description text not null,
  is_public boolean not null default false,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

insert into public.app_settings(key,value,description,is_public) values
 ('booking_approval_mode','"driver_approves"'::jsonb,'Driver must approve each booking request.',true),
 ('booking_pending_ttl_minutes','15'::jsonb,'Minutes before an unanswered booking request expires.',true),
 ('payment_mode','"cash_simulated"'::jsonb,'Prototype payment mode; no card processing is enabled.',true),
 ('boarding_confirmation_mode','"driver"'::jsonb,'Only the driver records boarding confirmation.',true),
 ('trip_completion_grace_minutes','10'::jsonb,'Grace period after estimated arrival before completion actions.',true),
 ('seat_allocation_mode','"per_segment"'::jsonb,'Capacity is enforced on every leg occupied by a booking.',true),
 ('location_retention_days','30'::jsonb,'Retention window for precise trip location records.',false),
 ('identity_document_retention_months_after_closure','12'::jsonb,'Retention target after account closure, subject to applicable law.',false),
 ('chat_retention_days_after_trip','30'::jsonb,'Messaging availability window after trip completion.',true)
on conflict (key) do nothing;

insert into public.allowed_status_transitions(entity_type,from_status,to_status,actor_role)
select v.entity_type,v.from_status,v.to_status,v.actor_role::public.app_role
from (values
 ('trip','draft','published','driver'),
 ('trip','draft','cancelled','driver'),
 ('trip','published','in_progress','driver'),
 ('trip','published','cancelled','driver'),
 ('trip','in_progress','completed','driver'),
 ('trip','in_progress','cancelled','driver'),
 ('booking','pending','confirmed','driver'),
 ('booking','pending','rejected','driver'),
 ('booking','pending','cancelled','rider'),
 ('booking','pending','cancelled','driver'),
 ('booking','pending','cancelled',null),
 ('booking','confirmed','cancelled','rider'),
 ('booking','confirmed','cancelled','driver'),
 ('booking','confirmed','cancelled',null),
 ('booking','confirmed','completed','driver'),
 ('booking','confirmed','no_show','driver')
) v(entity_type,from_status,to_status,actor_role)
where not exists (
  select 1 from public.allowed_status_transitions x
  where x.entity_type=v.entity_type and x.from_status=v.from_status
    and x.to_status=v.to_status and x.actor_role is not distinct from v.actor_role::public.app_role
);

alter table public.booking_segment_allocations enable row level security;
alter table public.app_settings enable row level security;
revoke all on table public.booking_segment_allocations, public.app_settings from public, anon, authenticated;
grant select on public.booking_segment_allocations to authenticated;
grant select on public.app_settings to authenticated;
create policy booking_allocations_participant_read on public.booking_segment_allocations for select to authenticated
using (exists (
  select 1 from public.bookings b join public.trips t on t.id=b.trip_id
  where b.id=booking_id and (b.passenger_id=(select auth.uid()) or t.driver_id=(select auth.uid()))
));
create policy app_settings_read_public on public.app_settings for select to authenticated using (is_public);

drop policy if exists bookings_cancel_own on public.bookings;
revoke insert, update, delete on public.bookings from authenticated;
grant select on public.bookings to authenticated;

-- Existing route data remains queryable through the canonical status name.
drop policy if exists trips_insert_as_approved_driver on public.trips;
drop policy if exists trips_update_as_approved_driver on public.trips;
drop policy if exists trips_read_open_or_owned on public.trips;
create policy trips_read_published_or_owned on public.trips for select to authenticated
using ((select auth.uid()) is not null and (status in ('published','in_progress') or driver_id=(select auth.uid())));
create policy trip_segments_read_published_or_owned on public.trip_segments for select to authenticated
using (exists(select 1 from public.trips t where t.id=trip_id and (t.status in ('published','in_progress') or t.driver_id=(select auth.uid()))));
revoke insert, update, delete on public.trips, public.trip_segments from public, anon, authenticated;
grant select on public.trips, public.trip_segments to authenticated;

create trigger set_updated_at before update on public.booking_segment_allocations
for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.app_settings
for each row execute function public.set_updated_at();

commit;
