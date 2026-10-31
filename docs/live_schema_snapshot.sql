-- RESTORABLE schema snapshot for a clean Supabase project.
-- Generated from the checked-in legacy baseline and the 28 recorded production
-- migrations. Replays 27 recorded migrations; intentionally omits
-- 20261031213104 (account_deletion_worker_schedule), because it hardcodes the
-- PRODUCTION Edge Function URL. Configure that job separately for the target project.
-- Existing data, Auth users, Storage objects, Edge Function code/secrets, and realtime
-- publication settings are not included.
-- Apply only to a new/test project. This is not a production migration.
-- Prerequisite: execute as the Supabase postgres role.

-- 0. Legacy schema baseline used for the test reconstruction.
-- ================================================================
-- On The Road — Database Schema for Supabase PostgreSQL
-- ================================================================

-- 1. جدول المستخدمين (Profiles)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT UNIQUE,
  role TEXT CHECK (role IN ('passenger', 'driver', 'admin')) DEFAULT 'passenger',
  avatar_url TEXT,
  verification_status TEXT CHECK (verification_status IN (
    'unverified', 'pending', 'approved', 'rejected', 'resubmission_required'
  )) DEFAULT 'unverified',
  national_id TEXT,
  id_front_url TEXT,
  id_back_url TEXT,
  selfie_url TEXT,
  license_url TEXT,
  car_model TEXT,
  car_color TEXT,
  car_plate TEXT,
  rating NUMERIC(3,2) DEFAULT 5.0,
  trips_count INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. جدول الرحلات (Trips)
CREATE TABLE IF NOT EXISTS public.trips (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  origin_city TEXT NOT NULL,
  destination_city TEXT NOT NULL,
  departure_time TIMESTAMPTZ NOT NULL,
  arrival_time TIMESTAMPTZ,
  total_seats INT NOT NULL DEFAULT 3,
  notes TEXT,
  status TEXT CHECK (status IN ('upcoming', 'active', 'completed', 'cancelled')) DEFAULT 'upcoming',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. جدول مقاطع الرحلة والأسعار (Trip Segments)
CREATE TABLE IF NOT EXISTS public.trip_segments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  from_city TEXT NOT NULL,
  to_city TEXT NOT NULL,
  segment_order INT NOT NULL,
  price NUMERIC(10,2) NOT NULL
);

-- 4. جدول الحجوزات (Bookings)
CREATE TABLE IF NOT EXISTS public.bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trip_id UUID NOT NULL REFERENCES public.trips(id) ON DELETE CASCADE,
  passenger_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  pickup_city TEXT NOT NULL,
  dropoff_city TEXT NOT NULL,
  pickup_order INT NOT NULL DEFAULT 1,
  dropoff_order INT NOT NULL DEFAULT 2,
  seats_booked INT NOT NULL DEFAULT 1,
  total_price NUMERIC(10,2) NOT NULL,
  status TEXT CHECK (status IN (
    'pending', 'confirmed', 'rejected', 'cancelled', 'completed', 'no_show'
  )) DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. جدول الرسائل والمحادثة (Messages)
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- 6. دالة حساب المقاعد المتاحة لكل مقطع (Core Seat Logic)
-- ================================================================
CREATE OR REPLACE FUNCTION available_seats(
  p_trip_id UUID,
  p_pickup_order INT,
  p_dropoff_order INT
) RETURNS INT AS $$
DECLARE
  v_total_seats INT;
  v_max_booked INT;
BEGIN
  SELECT total_seats INTO v_total_seats FROM public.trips WHERE id = p_trip_id;

  SELECT COALESCE(MAX(segment_booked), 0) INTO v_max_booked
  FROM (
    SELECT SUM(b.seats_booked) AS segment_booked
    FROM public.bookings b
    WHERE b.trip_id = p_trip_id
      AND b.status IN ('pending', 'confirmed')
      AND b.pickup_order < p_dropoff_order
      AND b.dropoff_order > p_pickup_order
  ) sub;

  RETURN GREATEST(0, v_total_seats - v_max_booked);
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- 7. تفعيل الحماية وسياسات الأمان (Row Level Security - RLS)
-- ================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- سياسات القراءة العامة للرحلات والمقاطع
CREATE POLICY "Public read trips" ON public.trips FOR SELECT USING (true);
CREATE POLICY "Public read segments" ON public.trip_segments FOR SELECT USING (true);
CREATE POLICY "Public read profiles" ON public.profiles FOR SELECT USING (true);

-- سياسات المستخدم لملفه وحجوزاته
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can view own bookings" ON public.bookings FOR SELECT USING (auth.uid() = passenger_id);
CREATE POLICY "Users can create bookings" ON public.bookings FOR INSERT WITH CHECK (auth.uid() = passenger_id);
CREATE POLICY "Drivers can view trip bookings" ON public.bookings FOR SELECT USING (
  auth.uid() IN (SELECT driver_id FROM public.trips WHERE id = trip_id)
);

-- 1. Enable RLS automatically on subsequently created public tables.
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
  tbl name;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
    IF cmd.schema_name IS NOT NULL
       AND cmd.schema_name IN ('public')
       AND cmd.schema_name NOT IN ('pg_catalog','information_schema')
       AND cmd.schema_name NOT LIKE 'pg_toast%'
       AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        SELECT c.relname INTO tbl FROM pg_catalog.pg_class c WHERE c.oid = cmd.objid;
        EXECUTE format('alter table if exists %I.%I enable row level security', cmd.schema_name, tbl);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION WHEN OTHERS THEN
        RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
    ELSE
      RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
    END IF;
  END LOOP;
END;
$function$;
CREATE EVENT TRIGGER ensure_rls
  ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION public.rls_auto_enable();

-- 2. Test-only prerequisite missing from the production migration ledger.
-- Required by later recorded workflow migrations; production evolved out-of-band.
begin;
alter table public.trip_segments add column if not exists segment_kind text;
alter table public.trip_segments drop constraint if exists trip_segments_segment_kind_check;
alter table public.trip_segments add constraint trip_segments_segment_kind_check
  check (segment_kind in ('leg', 'fare_override'));
create unique index if not exists trip_segments_unique_adjacent_leg
  on public.trip_segments (trip_id, segment_order) where segment_kind = 'leg';
create unique index if not exists trip_segments_unique_pair_fare
  on public.trip_segments (trip_id, from_city, to_city) where segment_kind = 'fare_override';
commit;


-- Recorded production migration 20261031170008: tighten_legacy_rls_and_driver_approval
-- Remove legacy permissive policies that override the restrictive policies.
DROP POLICY IF EXISTS "Public read profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Public read trips" ON public.trips;
DROP POLICY IF EXISTS "Public read segments" ON public.trip_segments;
DROP POLICY IF EXISTS "Users can create bookings" ON public.bookings;
DROP POLICY IF EXISTS "Drivers can view trip bookings" ON public.bookings;
DROP POLICY IF EXISTS "Users can view own bookings" ON public.bookings;

-- Keep trip publication limited to approved drivers.
DROP POLICY IF EXISTS trips_insert_as_owning_driver ON public.trips;
CREATE POLICY trips_insert_as_approved_driver
ON public.trips FOR INSERT TO authenticated
WITH CHECK (
  driver_id = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.role = 'driver'
      AND p.verification_status = 'approved'
  )
);

DROP POLICY IF EXISTS trips_update_as_owning_driver ON public.trips;
CREATE POLICY trips_update_as_approved_driver
ON public.trips FOR UPDATE TO authenticated
USING (
  driver_id = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.role = 'driver'
      AND p.verification_status = 'approved'
  )
)
WITH CHECK (
  driver_id = (SELECT auth.uid())
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND p.role = 'driver'
      AND p.verification_status = 'approved'
  )
);

-- The event trigger still owns and invokes this helper; application roles do not need EXECUTE.
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

-- Function body already uses schema-qualified table names; pin name resolution to catalog only.
ALTER FUNCTION public.available_seats(uuid, integer, integer) SET search_path = '';

-- Recorded production migration 20261031174208: private_identity_document_storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('identity-documents', 'identity-documents', false, 10485760, array['image/jpeg','image/png'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create policy "Users upload own identity documents"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'identity-documents'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "Users read own identity documents"
on storage.objects for select to authenticated
using (
  bucket_id = 'identity-documents'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "Users update own identity documents"
on storage.objects for update to authenticated
using (
  bucket_id = 'identity-documents'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'identity-documents'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "Users delete own identity documents"
on storage.objects for delete to authenticated
using (
  bucket_id = 'identity-documents'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

-- Recorded production migration 20261031174542: identity_verification_requests
create table public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_role text not null check (user_role in ('passenger', 'driver')),
  national_id text not null check (national_id ~ '^[0-9]{14}$'),
  date_of_birth date not null,
  id_front_path text not null,
  id_back_path text not null,
  selfie_path text not null,
  license_front_path text,
  license_back_path text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'resubmission_required')),
  reviewer_notes text,
  submitted_at timestamptz not null default now(),
  constraint driver_requires_license check (
    (user_role = 'passenger' and license_front_path is null and license_back_path is null)
    or
    (user_role = 'driver' and license_front_path is not null and license_back_path is not null)
  )
);

alter table public.verification_requests enable row level security;
revoke all on table public.verification_requests from public, anon, authenticated;
grant select (id, user_id, user_role, status, submitted_at) on public.verification_requests to authenticated;
grant insert (user_id, user_role, national_id, date_of_birth, id_front_path, id_back_path, selfie_path, license_front_path, license_back_path)
  on public.verification_requests to authenticated;

create policy "Users read own verification request"
on public.verification_requests for select to authenticated
using (user_id = (select auth.uid()));

create policy "Users submit own verification request"
on public.verification_requests for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = user_role
  )
  and status = 'pending'
  and reviewer_notes is null
);

-- Recorded production migration 20261031202753: phase1_accounts_roles_privacy
-- Phase 1: Accounts, roles, privacy, consent, notification preferences,
-- devices, and account deletion requests.
-- Additive migration: preserves existing profile rows and keeps the legacy
-- verification_requests insert contract while moving submitted PII into the
-- private details table.

begin;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_type t
    join pg_catalog.pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'app_role'
  ) then
    create type public.app_role as enum ('rider', 'driver', 'reviewer', 'admin');
  end if;
  if not exists (
    select 1 from pg_catalog.pg_type t
    join pg_catalog.pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public' and t.typname = 'account_deletion_status'
  ) then
    create type public.account_deletion_status as enum
      ('requested', 'processing', 'completed', 'rejected', 'cancelled');
  end if;
end;
$$;

alter table public.profiles
  add column if not exists locale text not null default 'ar',
  add column if not exists avatar_path text,
  add column if not exists rating_avg numeric(3,2) not null default 0,
  add column if not exists rating_count integer not null default 0,
  add column if not exists updated_at timestamptz not null default pg_catalog.now();
alter table public.profiles
  add constraint profiles_locale_check check (locale in ('ar', 'en')) not valid,
  add constraint profiles_rating_avg_check check (rating_avg between 0 and 5) not valid,
  add constraint profiles_rating_count_check check (rating_count >= 0) not valid;

create table if not exists public.user_private_details (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  full_legal_name text,
  national_id text,
  date_of_birth date,
  city text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint user_private_details_national_id_check
    check (national_id is null or national_id ~ '^[0-9]{14}$')
);

create table if not exists public.user_roles (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  role public.app_role not null,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint user_roles_user_role_key unique (user_id, role)
);

create table if not exists public.consent_records (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  consent_type text not null check (consent_type in ('terms', 'privacy')),
  document_version text not null check (length(btrim(document_version)) > 0),
  locale text not null check (locale in ('ar', 'en')),
  accepted_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint consent_records_user_version_key
    unique (user_id, consent_type, document_version)
);

create table if not exists public.notification_preferences (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  push_enabled boolean not null default true,
  booking_updates boolean not null default true,
  trip_updates boolean not null default true,
  safety_alerts boolean not null default true,
  support_updates boolean not null default true,
  marketing_messages boolean not null default false,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.device_tokens (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  fcm_token text not null unique check (length(btrim(fcm_token)) >= 16),
  platform text not null check (platform in ('android', 'ios', 'web')),
  last_seen_at timestamptz not null default pg_catalog.now(),
  is_active boolean not null default true,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.account_deletion_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  status public.account_deletion_status not null default 'requested',
  requested_at timestamptz not null default pg_catalog.now(),
  processed_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint account_deletion_processed_at_check
    check ((status in ('completed', 'rejected', 'cancelled')) = (processed_at is not null))
);

create unique index if not exists account_deletion_one_open_request
  on public.account_deletion_requests(user_id)
  where status in ('requested', 'processing');

create index if not exists user_roles_user_id_idx on public.user_roles(user_id);
create index if not exists consent_records_user_created_idx
  on public.consent_records(user_id, created_at desc);
create index if not exists device_tokens_user_active_idx
  on public.device_tokens(user_id, is_active);
create index if not exists account_deletion_requests_user_idx
  on public.account_deletion_requests(user_id, requested_at desc);
create index if not exists trips_driver_id_idx on public.trips(driver_id);
create index if not exists trip_segments_trip_order_idx on public.trip_segments(trip_id, segment_order);
create index if not exists bookings_passenger_created_idx on public.bookings(passenger_id, created_at desc);
create index if not exists bookings_trip_id_idx on public.bookings(trip_id);
create index if not exists messages_booking_created_idx on public.messages(booking_id, created_at);
create index if not exists messages_sender_id_idx on public.messages(sender_id);
create index if not exists verification_requests_user_submitted_idx
  on public.verification_requests(user_id, submitted_at desc);

insert into public.user_roles (user_id, role)
select p.id, 'rider'::public.app_role
from public.profiles p
on conflict (user_id, role) do nothing;

insert into public.user_roles (user_id, role)
select p.id,
       case p.role when 'admin' then 'admin'::public.app_role
                   when 'driver' then 'driver'::public.app_role
                   else 'rider'::public.app_role end
from public.profiles p
where p.role in ('driver', 'admin')
on conflict (user_id, role) do nothing;

do $$
begin
  if exists (
    select 1
    from public.profiles p
    join public.verification_requests vr on vr.user_id = p.id
    where p.national_id is not null
      and vr.national_id is not null
      and p.national_id <> vr.national_id
  ) then
    raise exception 'Conflicting legacy identity numbers found; resolve the conflict before migrating PII.';
  end if;
end;
$$;

alter table public.verification_requests
  alter column national_id drop not null,
  alter column date_of_birth drop not null;

insert into public.user_private_details (user_id, national_id, date_of_birth)
select p.id,
       coalesce(p.national_id, vr.national_id),
       vr.date_of_birth
from public.profiles p
left join lateral (
  select v.national_id, v.date_of_birth
  from public.verification_requests v
  where v.user_id = p.id
  order by v.submitted_at desc
  limit 1
) vr on true
on conflict (user_id) do update
set national_id = coalesce(user_private_details.national_id, excluded.national_id),
    date_of_birth = coalesce(user_private_details.date_of_birth, excluded.date_of_birth);

update public.profiles set national_id = null where national_id is not null;
update public.verification_requests
set national_id = null, date_of_birth = null
where national_id is not null or date_of_birth is not null;

create or replace function public.capture_private_verification_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if auth.uid() is null or new.user_id is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'Cannot submit another user verification data.';
  end if;
  insert into public.user_private_details (user_id, national_id, date_of_birth)
  values (new.user_id, new.national_id, new.date_of_birth)
  on conflict (user_id) do update
    set national_id = excluded.national_id,
        date_of_birth = excluded.date_of_birth;
  new.national_id := null;
  new.date_of_birth := null;
  return new;
end;
$$;
revoke all on function public.capture_private_verification_fields() from public, anon, authenticated;
drop trigger if exists verification_requests_capture_private_fields on public.verification_requests;
create trigger verification_requests_capture_private_fields
before insert on public.verification_requests
for each row execute function public.capture_private_verification_fields();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;
revoke all on function public.set_updated_at() from public, anon, authenticated;

do $$
declare
  t record;
begin
  for t in
    select c.relname
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
  loop
    execute pg_catalog.format('alter table public.%I add column if not exists created_at timestamptz default pg_catalog.now()', t.relname);
    execute pg_catalog.format('alter table public.%I add column if not exists updated_at timestamptz default pg_catalog.now()', t.relname);
    execute pg_catalog.format('update public.%I set created_at = coalesce(created_at, pg_catalog.now()), updated_at = coalesce(updated_at, created_at, pg_catalog.now()) where created_at is null or updated_at is null', t.relname);
    execute pg_catalog.format('alter table public.%I alter column created_at set default pg_catalog.now(), alter column created_at set not null, alter column updated_at set default pg_catalog.now(), alter column updated_at set not null', t.relname);
    execute pg_catalog.format('drop trigger if exists set_updated_at on public.%I', t.relname);
    execute pg_catalog.format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()', t.relname);
  end loop;
end;
$$;

create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, name, phone, role)
  values (
    new.id,
    coalesce(nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'name'), ''), nullif(new.phone, ''), 'New user'),
    new.phone,
    'passenger'
  )
  on conflict (id) do nothing;

  insert into public.user_roles (user_id, role)
  values (new.id, 'rider'::public.app_role)
  on conflict (user_id, role) do nothing;

  insert into public.user_private_details (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;
revoke all on function public.handle_new_auth_user_profile() from public, anon, authenticated;
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.handle_new_auth_user_profile();

create or replace function public.has_role(p_role public.app_role)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1 from public.user_roles ur
    where ur.user_id = auth.uid() and ur.role = p_role
  );
$$;
revoke all on function public.has_role(public.app_role) from public, anon, authenticated;
grant execute on function public.has_role(public.app_role) to authenticated;

create or replace function public.is_admin()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select public.has_role('admin'::public.app_role);
$$;
revoke all on function public.is_admin() from public, anon, authenticated;
grant execute on function public.is_admin() to authenticated;

drop policy if exists profiles_select_approved_driver_directory on public.profiles;
create policy profiles_select_approved_driver_directory
  on public.profiles for select to authenticated
  using (role = 'driver' and verification_status = 'approved');

revoke all on table public.profiles from public, anon, authenticated;
grant select (id, name, avatar_url, avatar_path, rating, rating_avg, rating_count, trips_count, car_model, car_color, created_at, updated_at, locale, role, verification_status)
  on public.profiles to authenticated;
grant update (name, avatar_url, avatar_path, locale)
  on public.profiles to authenticated;

create or replace view public.driver_public_profiles
with (security_invoker = true, security_barrier = true)
as
select id, name, avatar_url, rating, trips_count, car_model, car_color
from public.profiles
where role = 'driver' and verification_status = 'approved';
revoke all on table public.driver_public_profiles from public, anon, authenticated;
grant select on table public.driver_public_profiles to authenticated;

create or replace view public.public_driver_profiles
with (security_invoker = true, security_barrier = true)
as
select id, name, avatar_url, avatar_path, rating_avg, rating_count, trips_count, car_model, car_color
from public.profiles
where role = 'driver' and verification_status = 'approved';
revoke all on table public.public_driver_profiles from public, anon, authenticated;
grant select on table public.public_driver_profiles to authenticated;

do $$
declare t text;
begin
  foreach t in array array['user_private_details','user_roles','consent_records','notification_preferences','device_tokens','account_deletion_requests'] loop
    execute pg_catalog.format('alter table public.%I enable row level security', t);
    execute pg_catalog.format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
end;
$$;

grant select on public.user_private_details to authenticated;
grant insert (user_id, full_legal_name, national_id, date_of_birth, city) on public.user_private_details to authenticated;
grant update (full_legal_name, national_id, date_of_birth, city) on public.user_private_details to authenticated;
create policy user_private_details_select_own on public.user_private_details for select to authenticated using (user_id = (select auth.uid()));
create policy user_private_details_insert_own on public.user_private_details for insert to authenticated with check (user_id = (select auth.uid()));
create policy user_private_details_update_own on public.user_private_details for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select on public.user_roles to authenticated;
create policy user_roles_select_own on public.user_roles for select to authenticated using (user_id = (select auth.uid()));

grant select on public.consent_records to authenticated;
grant insert (user_id, consent_type, document_version, locale) on public.consent_records to authenticated;
create policy consent_records_select_own on public.consent_records for select to authenticated using (user_id = (select auth.uid()));
create policy consent_records_insert_own on public.consent_records for insert to authenticated with check (user_id = (select auth.uid()));

grant select on public.notification_preferences to authenticated;
grant update (push_enabled, booking_updates, trip_updates, safety_alerts, support_updates, marketing_messages)
  on public.notification_preferences to authenticated;
create policy notification_preferences_select_own on public.notification_preferences for select to authenticated using (user_id = (select auth.uid()));
create policy notification_preferences_update_own on public.notification_preferences for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

grant select on public.device_tokens to authenticated;
grant insert (user_id, fcm_token, platform, last_seen_at, is_active) on public.device_tokens to authenticated;
grant update (fcm_token, platform, last_seen_at, is_active) on public.device_tokens to authenticated;
grant delete on public.device_tokens to authenticated;
create policy device_tokens_select_own on public.device_tokens for select to authenticated using (user_id = (select auth.uid()));
create policy device_tokens_insert_own on public.device_tokens for insert to authenticated with check (user_id = (select auth.uid()));
create policy device_tokens_update_own on public.device_tokens for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy device_tokens_delete_own on public.device_tokens for delete to authenticated using (user_id = (select auth.uid()));

grant select on public.account_deletion_requests to authenticated;
grant insert (user_id) on public.account_deletion_requests to authenticated;
create policy account_deletion_requests_select_own on public.account_deletion_requests for select to authenticated using (user_id = (select auth.uid()));
create policy account_deletion_requests_insert_own on public.account_deletion_requests for insert to authenticated with check (user_id = (select auth.uid()) and status = 'requested'::public.account_deletion_status and processed_at is null);

revoke select (phone, national_id, id_front_url, id_back_url, selfie_url, license_url, car_plate)
  on public.profiles from authenticated;
revoke update (phone, role, verification_status, national_id, id_front_url, id_back_url, selfie_url, license_url, car_model, car_color, car_plate, rating, trips_count)
  on public.profiles from authenticated;

revoke select (national_id, date_of_birth, id_front_path, id_back_path, selfie_path, license_front_path, license_back_path, reviewer_notes)
  on public.verification_requests from authenticated;

commit;

-- Recorded production migration 20261031202849: phase1_privilege_tightening
-- Phase 1 follow-up: close direct status writes, remove an avoidable
-- SECURITY DEFINER helper, and tighten profile policy evaluation.
begin;

drop index if exists public.user_roles_user_id_idx;
create index if not exists user_roles_assigned_by_idx on public.user_roles(assigned_by);

-- Replace the two permissive profile SELECT policies with one equivalent
-- owner-or-approved-driver policy.
drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_select_approved_driver_directory on public.profiles;
create policy profiles_select_owner_or_approved_driver
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or (role = 'driver' and verification_status = 'approved')
  );

-- The helper now respects trips RLS. The explicit owner policy allows a driver
-- to see their own non-published trips and prevents the helper from bypassing RLS.
drop policy if exists trips_select_own_driver on public.trips;
create policy trips_select_own_driver
  on public.trips for select to authenticated
  using (driver_id = (select auth.uid()));

create or replace function public.is_own_trip(p_trip_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.trips t
    where t.id = p_trip_id
      and t.driver_id = auth.uid()
  );
$$;
revoke all on function public.is_own_trip(uuid) from public, anon, authenticated;
grant execute on function public.is_own_trip(uuid) to authenticated;

-- Lifecycle changes and trip publication must pass through validated RPCs.
revoke insert on table public.trips from authenticated;
revoke insert (driver_id, origin_city, destination_city, departure_time, arrival_time, total_seats, notes, status)
  on table public.trips from authenticated;
revoke update (status) on table public.trips from authenticated;
revoke update (status) on table public.bookings from authenticated;

commit;

-- Recorded production migration 20261031202905: phase1_trip_read_policy_merge
begin;
drop policy if exists trips_read_open_authenticated on public.trips;
drop policy if exists trips_select_own_driver on public.trips;
create policy trips_read_open_or_owned
  on public.trips for select to authenticated
  using (
    (select auth.uid()) is not null
    and (status = 'upcoming' or driver_id = (select auth.uid()))
  );
commit;

-- Recorded production migration 20261031203345: phase2_verification_drivers_vehicles
-- Phase 2: verification, reviewer assignments, driver capability, and vehicles.
begin;

-- The client insert contract remains available while status becomes an enum.
drop policy if exists "Users read own verification request" on public.verification_requests;
drop policy if exists "Users submit own verification request" on public.verification_requests;

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='verification_status') then
    create type public.verification_status as enum ('draft','submitted','in_review','needs_resubmission','approved','rejected');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='verification_document_type') then
    create type public.verification_document_type as enum ('national_id_front','national_id_back','face_scan','driver_license_front','driver_license_back','vehicle_license_front','vehicle_license_back');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='document_review_status') then
    create type public.document_review_status as enum ('submitted','accepted','rejected','needs_resubmission');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='driver_profile_status') then
    create type public.driver_profile_status as enum ('draft','submitted','in_review','needs_resubmission','approved','rejected','suspended');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='vehicle_status') then
    create type public.vehicle_status as enum ('draft','submitted','in_review','needs_resubmission','approved','rejected','suspended');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='verification_decision') then
    create type public.verification_decision as enum ('approved','rejected','needs_resubmission');
  end if;
end $$;

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create table public.allowed_status_transitions (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_type text not null check(entity_type in ('verification','driver_profile','vehicle','trip','booking','deletion')),
  from_status text not null,
  to_status text not null,
  actor_role public.app_role,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique(entity_type,from_status,to_status,actor_role),
  check(from_status<>to_status)
);
create table public.audit_log (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null check(length(btrim(action))>0),
  entity_type text not null,
  entity_id uuid,
  occurred_at timestamptz not null default pg_catalog.now(),
  metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);
create table public.driver_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  verification_request_id uuid references public.verification_requests(id) on delete set null,
  status public.driver_profile_status not null default 'draft',
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check((status='approved')=(approved_at is not null))
);
create table public.vehicles (
  id uuid primary key default extensions.gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  make text not null check(length(btrim(make)) between 1 and 60),
  model text not null check(length(btrim(model)) between 1 and 80),
  color text not null check(length(btrim(color)) between 1 and 40),
  plate text not null check(length(btrim(plate)) between 3 and 24),
  manufacture_year smallint check(manufacture_year between 1980 and extract(year from pg_catalog.now())::integer+1),
  seats smallint not null check(seats between 1 and 8),
  status public.vehicle_status not null default 'draft',
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check((status='approved')=(approved_at is not null and approved_by is not null))
);
create table public.reviewer_assignments (
  id uuid primary key default extensions.gen_random_uuid(),
  reviewer_id uuid not null references public.profiles(id) on delete cascade,
  verification_request_id uuid references public.verification_requests(id) on delete cascade,
  vehicle_id uuid references public.vehicles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check(num_nonnulls(verification_request_id,vehicle_id)=1),
  unique(reviewer_id,verification_request_id),
  unique(reviewer_id,vehicle_id)
);
create table public.verification_documents (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  verification_request_id uuid not null references public.verification_requests(id) on delete cascade,
  document_type public.verification_document_type not null,
  storage_path text not null unique,
  version integer not null default 1 check(version>0),
  status public.document_review_status not null default 'submitted',
  uploaded_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique(verification_request_id,document_type,version)
);
create table public.vehicle_documents (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  document_type public.verification_document_type not null check(document_type in ('vehicle_license_front','vehicle_license_back')),
  storage_path text not null unique,
  version integer not null default 1 check(version>0),
  status public.document_review_status not null default 'submitted',
  uploaded_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique(vehicle_id,document_type,version)
);
create table public.verification_checks (
  id uuid primary key default extensions.gen_random_uuid(),
  verification_request_id uuid not null references public.verification_requests(id) on delete cascade,
  check_type text not null check(check_type in ('ocr','document_consistency','face_match','liveness')),
  provider text not null,
  result text not null check(result in ('pending','passed','failed','needs_human_review','error')),
  score numeric(5,4) check(score between 0 and 1),
  extracted_fields jsonb not null default '{}'::jsonb check(jsonb_typeof(extracted_fields)='object'),
  is_preliminary boolean not null default true check(is_preliminary),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);
create table public.verification_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  verification_request_id uuid references public.verification_requests(id) on delete cascade,
  vehicle_id uuid references public.vehicles(id) on delete cascade,
  decision public.verification_decision not null,
  reviewer_notes text,
  decided_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check(num_nonnulls(verification_request_id,vehicle_id)=1)
);

-- Convert old text states without deleting rows. 'pending' represented a new
-- request; 'resubmission_required' maps to the explicit new enum value.
alter table public.verification_requests drop constraint if exists verification_requests_status_check;
alter table public.verification_requests alter column status drop default;
alter table public.verification_requests alter column status type public.verification_status using
  (case status when 'pending' then 'submitted' when 'resubmission_required' then 'needs_resubmission' else status end)::public.verification_status;
alter table public.verification_requests alter column status set default 'submitted'::public.verification_status;

insert into public.allowed_status_transitions(entity_type,from_status,to_status) values
 ('verification','draft','submitted'),('verification','submitted','in_review'),('verification','submitted','approved'),('verification','submitted','rejected'),('verification','submitted','needs_resubmission'),
 ('verification','in_review','approved'),('verification','in_review','rejected'),('verification','in_review','needs_resubmission'),('verification','needs_resubmission','submitted'),
 ('driver_profile','draft','submitted'),('driver_profile','submitted','in_review'),('driver_profile','submitted','approved'),('driver_profile','submitted','rejected'),('driver_profile','in_review','approved'),('driver_profile','in_review','rejected'),('driver_profile','in_review','needs_resubmission'),('driver_profile','needs_resubmission','submitted'),
 ('vehicle','draft','submitted'),('vehicle','submitted','in_review'),('vehicle','submitted','approved'),('vehicle','submitted','rejected'),('vehicle','in_review','approved'),('vehicle','in_review','rejected'),('vehicle','in_review','needs_resubmission'),('vehicle','needs_resubmission','submitted')
on conflict do nothing;

-- Migrate the existing approved-driver designation. Vehicle approval remains
-- separate; no vehicle is inferred from the old profile fields.
insert into public.driver_profiles(user_id,status,approved_at)
select id,'approved'::public.driver_profile_status,created_at
from public.profiles where role='driver' and verification_status='approved'
on conflict(user_id) do nothing;

create index on public.allowed_status_transitions(entity_type,from_status);
create index on public.audit_log(entity_type,entity_id,occurred_at desc);
create index on public.driver_profiles(status);
create index on public.vehicles(owner_id,created_at desc);
create index on public.vehicles(status);
create index on public.reviewer_assignments(reviewer_id,assigned_at desc);
create index on public.reviewer_assignments(verification_request_id);
create index on public.reviewer_assignments(vehicle_id);
create index on public.verification_documents(verification_request_id);
create index on public.verification_documents(user_id);
create index on public.vehicle_documents(vehicle_id);
create index on public.vehicle_documents(user_id);
create index on public.verification_checks(verification_request_id,created_at desc);
create index on public.verification_reviews(verification_request_id,decided_at desc);
create index on public.verification_reviews(vehicle_id,decided_at desc);

do $$ declare t text; begin
  foreach t in array array['allowed_status_transitions','audit_log','driver_profiles','vehicles','reviewer_assignments','verification_documents','vehicle_documents','verification_checks','verification_reviews'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
  end loop;
end $$;

create or replace function public.is_reviewer_for_verification(p_request_id uuid)
returns boolean language sql stable security invoker set search_path=''
as $$ select auth.uid() is not null and public.has_role('reviewer'::public.app_role) and exists(select 1 from public.reviewer_assignments ra where ra.reviewer_id=auth.uid() and ra.verification_request_id=p_request_id); $$;
revoke all on function public.is_reviewer_for_verification(uuid) from public,anon,authenticated;
grant execute on function public.is_reviewer_for_verification(uuid) to authenticated;
create or replace function public.is_reviewer_for_vehicle(p_vehicle_id uuid)
returns boolean language sql stable security invoker set search_path=''
as $$ select auth.uid() is not null and public.has_role('reviewer'::public.app_role) and exists(select 1 from public.reviewer_assignments ra where ra.reviewer_id=auth.uid() and ra.vehicle_id=p_vehicle_id); $$;
revoke all on function public.is_reviewer_for_vehicle(uuid) from public,anon,authenticated;
grant execute on function public.is_reviewer_for_vehicle(uuid) to authenticated;
create or replace function public.can_transition(p_entity text,p_from text,p_to text)
returns boolean language sql stable security invoker set search_path=''
as $$ select exists(select 1 from public.allowed_status_transitions x where x.entity_type=p_entity and x.from_status=p_from and x.to_status=p_to); $$;
revoke all on function public.can_transition(text,text,text) from public,anon,authenticated;
grant execute on function public.can_transition(text,text,text) to authenticated;

grant select on public.allowed_status_transitions to authenticated;
create policy allowed_status_transitions_read on public.allowed_status_transitions for select to authenticated using(true);

grant select(id,user_id,user_role,status,submitted_at,created_at,updated_at) on public.verification_requests to authenticated;
create policy verification_requests_owner_or_reviewer_read on public.verification_requests for select to authenticated using(user_id=(select auth.uid()) or public.is_reviewer_for_verification(id) or public.is_admin());
create policy verification_requests_submit_own on public.verification_requests for insert to authenticated with check(user_id=(select auth.uid()) and status='submitted'::public.verification_status and reviewer_notes is null);

grant select(id,user_id,verification_request_id,document_type,storage_path,version,status,uploaded_at,created_at,updated_at) on public.verification_documents to authenticated;
create policy verification_documents_owner_or_reviewer_read on public.verification_documents for select to authenticated using(user_id=(select auth.uid()) or public.is_reviewer_for_verification(verification_request_id) or public.is_admin());
grant select(id,verification_request_id,check_type,provider,result,score,extracted_fields,is_preliminary,created_at) on public.verification_checks to authenticated;
create policy verification_checks_owner_or_reviewer_read on public.verification_checks for select to authenticated using(exists(select 1 from public.verification_requests vr where vr.id=verification_request_id and vr.user_id=(select auth.uid())) or public.is_reviewer_for_verification(verification_request_id) or public.is_admin());
grant insert(verification_request_id,check_type,provider,result,score,extracted_fields,is_preliminary) on public.verification_checks to service_role;
grant update(result,score,extracted_fields) on public.verification_checks to service_role;

grant select on public.driver_profiles to authenticated;
grant insert(user_id,verification_request_id) on public.driver_profiles to authenticated;
create policy driver_profiles_owner_or_approved_read on public.driver_profiles for select to authenticated using(user_id=(select auth.uid()) or status='approved' or public.is_admin());
create policy driver_profiles_owner_submit on public.driver_profiles for insert to authenticated with check(user_id=(select auth.uid()) and status='draft' and approved_at is null and approved_by is null);

grant select(id,owner_id,make,model,color,plate,manufacture_year,seats,status,approved_at,approved_by,created_at,updated_at) on public.vehicles to authenticated;
grant insert(owner_id,make,model,color,plate,manufacture_year,seats) on public.vehicles to authenticated;
grant update(make,model,color,plate,manufacture_year,seats) on public.vehicles to authenticated;
create policy vehicles_owner_or_approved_read on public.vehicles for select to authenticated using(owner_id=(select auth.uid()) or status='approved' or public.is_admin());
create policy vehicles_owner_insert_draft on public.vehicles for insert to authenticated with check(owner_id=(select auth.uid()) and status='draft' and approved_at is null and approved_by is null);
create policy vehicles_owner_update_draft on public.vehicles for update to authenticated using(owner_id=(select auth.uid()) and status in ('draft','needs_resubmission')) with check(owner_id=(select auth.uid()) and status in ('draft','needs_resubmission'));

grant select on public.reviewer_assignments to authenticated;
create policy reviewer_assignments_assigned_or_admin_read on public.reviewer_assignments for select to authenticated using(reviewer_id=(select auth.uid()) or public.is_admin());
grant select on public.vehicle_documents to authenticated;
grant insert(user_id,vehicle_id,document_type,storage_path,version) on public.vehicle_documents to authenticated;
create policy vehicle_documents_owner_or_reviewer_read on public.vehicle_documents for select to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.reviewer_assignments ra where ra.vehicle_id=vehicle_documents.vehicle_id and ra.reviewer_id=(select auth.uid())) or public.is_admin());
create policy vehicle_documents_owner_insert on public.vehicle_documents for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.vehicles v where v.id=vehicle_id and v.owner_id=(select auth.uid()) and v.status in ('draft','needs_resubmission')));
grant select on public.verification_reviews to authenticated;
create policy verification_reviews_reviewer_or_admin_read on public.verification_reviews for select to authenticated using(public.is_admin() or (reviewer_id=(select auth.uid()) and ((verification_request_id is not null and public.is_reviewer_for_verification(verification_request_id)) or (vehicle_id is not null and exists(select 1 from public.reviewer_assignments ra where ra.vehicle_id=verification_reviews.vehicle_id and ra.reviewer_id=(select auth.uid()))))));
grant select on public.audit_log to authenticated;
create policy audit_log_admin_read on public.audit_log for select to authenticated using(public.is_admin());

drop policy if exists profiles_select_owner_or_approved_driver on public.profiles;
create policy profiles_select_owner_or_approved_driver on public.profiles for select to authenticated using(id=(select auth.uid()) or exists(select 1 from public.driver_profiles dp where dp.user_id=profiles.id and dp.status='approved'));
create or replace view public.driver_public_profiles with(security_invoker=true,security_barrier=true) as
select p.id,p.name,p.avatar_url,p.rating,p.trips_count,p.car_model,p.car_color from public.profiles p join public.driver_profiles dp on dp.user_id=p.id where dp.status='approved';
create or replace view public.public_driver_profiles with(security_invoker=true,security_barrier=true) as
select p.id,p.name,p.avatar_url,p.avatar_path,p.rating_avg,p.rating_count,p.trips_count,p.car_model,p.car_color from public.profiles p join public.driver_profiles dp on dp.user_id=p.id where dp.status='approved';
revoke all on public.driver_public_profiles,public.public_driver_profiles from public,anon,authenticated;
grant select on public.driver_public_profiles,public.public_driver_profiles to authenticated;

create or replace function private.capture_verification_documents()
returns trigger language plpgsql security definer set search_path=''
as $$ begin
  if auth.uid() is null or auth.uid() is distinct from new.user_id then raise exception using errcode='42501',message='Cannot submit another user verification request.'; end if;
  insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path) values
    (new.user_id,new.id,'national_id_front',new.id_front_path),(new.user_id,new.id,'national_id_back',new.id_back_path),(new.user_id,new.id,'face_scan',new.selfie_path)
    on conflict(verification_request_id,document_type,version) do nothing;
  if new.license_front_path is not null then insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path) values(new.user_id,new.id,'driver_license_front',new.license_front_path) on conflict(verification_request_id,document_type,version) do nothing; end if;
  if new.license_back_path is not null then insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path) values(new.user_id,new.id,'driver_license_back',new.license_back_path) on conflict(verification_request_id,document_type,version) do nothing; end if;
  update public.verification_requests set id_front_path=null,id_back_path=null,selfie_path=null,license_front_path=null,license_back_path=null where id=new.id;
  if new.user_role='driver' then insert into public.driver_profiles(user_id,verification_request_id,status) values(new.user_id,new.id,'submitted') on conflict(user_id) do update set verification_request_id=excluded.verification_request_id; end if;
  return null;
end $$;
revoke all on function private.capture_verification_documents() from public,anon,authenticated;
create trigger verification_requests_normalize_documents after insert on public.verification_requests for each row execute function private.capture_verification_documents();

-- Preserve any existing document references before removing them from the legacy row.
insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path)
select user_id,id,'national_id_front'::public.verification_document_type,id_front_path from public.verification_requests where id_front_path is not null
union all select user_id,id,'national_id_back'::public.verification_document_type,id_back_path from public.verification_requests where id_back_path is not null
union all select user_id,id,'face_scan'::public.verification_document_type,selfie_path from public.verification_requests where selfie_path is not null
union all select user_id,id,'driver_license_front'::public.verification_document_type,license_front_path from public.verification_requests where license_front_path is not null
union all select user_id,id,'driver_license_back'::public.verification_document_type,license_back_path from public.verification_requests where license_back_path is not null
on conflict(verification_request_id,document_type,version) do nothing;
update public.verification_requests set id_front_path=null,id_back_path=null,selfie_path=null,license_front_path=null,license_back_path=null where id_front_path is not null or id_back_path is not null or selfie_path is not null or license_front_path is not null or license_back_path is not null;

create or replace function public.assign_verification_reviewer(p_request_id uuid,p_reviewer_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin') then raise exception using errcode='42501',message='Administrator role required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=p_reviewer_id and role='reviewer') then raise exception using errcode='22023',message='Target user is not a reviewer.'; end if;
  if not exists(select 1 from public.verification_requests where id=p_request_id and status in ('submitted','in_review')) then raise exception using errcode='22023',message='Request is not reviewable.'; end if;
  insert into public.reviewer_assignments(reviewer_id,verification_request_id,assigned_by) values(p_reviewer_id,p_request_id,auth.uid()) on conflict(reviewer_id,verification_request_id) do update set assigned_at=pg_catalog.now() returning id into v_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'verification_reviewer_assigned','verification_request',p_request_id,jsonb_build_object('reviewer_id',p_reviewer_id)); return v_id;
end $$;
revoke all on function public.assign_verification_reviewer(uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_verification_reviewer(uuid,uuid) to authenticated;

create or replace function public.assign_vehicle_reviewer(p_vehicle_id uuid,p_reviewer_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin') then raise exception using errcode='42501',message='Administrator role required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=p_reviewer_id and role='reviewer') then raise exception using errcode='22023',message='Target user is not a reviewer.'; end if;
  if not exists(select 1 from public.vehicles where id=p_vehicle_id and status in ('submitted','in_review')) then raise exception using errcode='22023',message='Vehicle is not reviewable.'; end if;
  insert into public.reviewer_assignments(reviewer_id,vehicle_id,assigned_by) values(p_reviewer_id,p_vehicle_id,auth.uid()) on conflict(reviewer_id,vehicle_id) do update set assigned_at=pg_catalog.now() returning id into v_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'vehicle_reviewer_assigned','vehicle',p_vehicle_id,jsonb_build_object('reviewer_id',p_reviewer_id)); return v_id;
end $$;
revoke all on function public.assign_vehicle_reviewer(uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_vehicle_reviewer(uuid,uuid) to authenticated;

create or replace function public.review_verification_request(p_request_id uuid,p_decision public.verification_decision,p_notes text default null)
returns public.verification_status language plpgsql security definer set search_path=''
as $$ declare v public.verification_requests%rowtype; v_to public.verification_status; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  if not exists(select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role in ('admin','reviewer')) then raise exception using errcode='42501',message='Reviewer or administrator role required.'; end if;
  select * into v from public.verification_requests where id=p_request_id for update;
  if not found then raise exception using errcode='P0002',message='Request not found.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin') and not exists(select 1 from public.reviewer_assignments where reviewer_id=auth.uid() and verification_request_id=p_request_id) then raise exception using errcode='42501',message='Request is not assigned to this reviewer.'; end if;
  v_to:=p_decision::text::public.verification_status;
  if not exists(select 1 from public.allowed_status_transitions where entity_type='verification' and from_status=v.status::text and to_status=v_to::text) then raise exception using errcode='22023',message='Invalid verification transition.'; end if;
  update public.verification_requests set status=v_to,reviewer_notes=p_notes where id=p_request_id;
  insert into public.verification_reviews(reviewer_id,verification_request_id,decision,reviewer_notes) values(auth.uid(),p_request_id,p_decision,p_notes);
  if v.user_role='driver' then
    insert into public.driver_profiles(user_id,verification_request_id,status,approved_at,approved_by)
    values(v.user_id,p_request_id,case p_decision when 'approved' then 'approved'::public.driver_profile_status when 'rejected' then 'rejected'::public.driver_profile_status else 'needs_resubmission'::public.driver_profile_status end,case when p_decision='approved' then pg_catalog.now() else null end,case when p_decision='approved' then auth.uid() else null end)
    on conflict(user_id) do update set verification_request_id=excluded.verification_request_id,status=excluded.status,approved_at=excluded.approved_at,approved_by=excluded.approved_by;
  end if;
  update public.profiles set verification_status=case p_decision when 'approved' then 'approved' when 'rejected' then 'rejected' else 'resubmission_required' end,role=case when v.user_role='driver' and p_decision='approved' then 'driver' else role end where id=v.user_id;
  if v.user_role='driver' and p_decision='approved' then insert into public.user_roles(user_id,role,assigned_by) values(v.user_id,'driver'::public.app_role,auth.uid()) on conflict(user_id,role) do nothing; end if;
  if v.user_role='driver' and p_decision='rejected' then delete from public.user_roles where user_id=v.user_id and role='driver'; end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'verification_decided','verification_request',p_request_id,jsonb_build_object('decision',p_decision::text,'user_role',v.user_role));
  return v_to;
end $$;
revoke all on function public.review_verification_request(uuid,public.verification_decision,text) from public,anon,authenticated;
grant execute on function public.review_verification_request(uuid,public.verification_decision,text) to authenticated;

create or replace function public.submit_vehicle_for_review(p_vehicle_id uuid)
returns public.vehicle_status language plpgsql security definer set search_path=''
as $$ declare v public.vehicles%rowtype; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  select * into v from public.vehicles where id=p_vehicle_id for update;
  if not found or v.owner_id<>auth.uid() then raise exception using errcode='42501',message='Vehicle not found or not owned by caller.'; end if;
  if not exists(select 1 from public.allowed_status_transitions where entity_type='vehicle' and from_status=v.status::text and to_status='submitted') then raise exception using errcode='22023',message='Vehicle cannot be submitted from current status.'; end if;
  if not exists(select 1 from public.vehicle_documents where vehicle_id=p_vehicle_id and document_type='vehicle_license_front') or not exists(select 1 from public.vehicle_documents where vehicle_id=p_vehicle_id and document_type='vehicle_license_back') then raise exception using errcode='22023',message='Both vehicle license sides are required.'; end if;
  update public.vehicles set status='submitted' where id=p_vehicle_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'vehicle_submitted','vehicle',p_vehicle_id); return 'submitted'::public.vehicle_status;
end $$;
revoke all on function public.submit_vehicle_for_review(uuid) from public,anon,authenticated;
grant execute on function public.submit_vehicle_for_review(uuid) to authenticated;

create or replace function public.review_vehicle(p_vehicle_id uuid,p_decision public.verification_decision,p_notes text default null)
returns public.vehicle_status language plpgsql security definer set search_path=''
as $$ declare v public.vehicles%rowtype; v_to public.vehicle_status; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','reviewer')) then raise exception using errcode='42501',message='Reviewer or administrator role required.'; end if;
  select * into v from public.vehicles where id=p_vehicle_id for update;
  if not found then raise exception using errcode='P0002',message='Vehicle not found.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin') and not exists(select 1 from public.reviewer_assignments where reviewer_id=auth.uid() and vehicle_id=p_vehicle_id) then raise exception using errcode='42501',message='Vehicle is not assigned to this reviewer.'; end if;
  v_to:=p_decision::text::public.vehicle_status;
  if not exists(select 1 from public.allowed_status_transitions where entity_type='vehicle' and from_status=v.status::text and to_status=v_to::text) then raise exception using errcode='22023',message='Invalid vehicle transition.'; end if;
  update public.vehicles set status=v_to,approved_at=case when v_to='approved' then pg_catalog.now() else null end,approved_by=case when v_to='approved' then auth.uid() else null end where id=p_vehicle_id;
  update public.vehicle_documents set status=case p_decision when 'approved' then 'accepted'::public.document_review_status when 'rejected' then 'rejected'::public.document_review_status else 'needs_resubmission'::public.document_review_status end where vehicle_id=p_vehicle_id;
  insert into public.verification_reviews(reviewer_id,vehicle_id,decision,reviewer_notes) values(auth.uid(),p_vehicle_id,p_decision,p_notes);
  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'vehicle_decided','vehicle',p_vehicle_id,jsonb_build_object('decision',p_decision::text)); return v_to;
end $$;
revoke all on function public.review_vehicle(uuid,public.verification_decision,text) from public,anon,authenticated;
grant execute on function public.review_vehicle(uuid,public.verification_decision,text) to authenticated;

-- Audit records cannot be changed or removed through ordinary table access.
create or replace function private.prevent_audit_log_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin raise exception using errcode='42501',message='Audit log rows are append-only.'; end $$;
revoke all on function private.prevent_audit_log_mutation() from public,anon,authenticated;
create trigger audit_log_no_update before update or delete on public.audit_log for each row execute function private.prevent_audit_log_mutation();

-- Storage buckets and exact object policies.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('vehicle-documents','vehicle-documents',false,10485760,array['image/jpeg','image/png','image/webp']),
 ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
create policy reviewer_read_assigned_identity_documents on storage.objects for select to authenticated using(bucket_id='identity-documents' and exists(select 1 from public.verification_documents d where d.storage_path=name and public.is_reviewer_for_verification(d.verification_request_id)));
create policy vehicle_docs_owner_read on storage.objects for select to authenticated using(bucket_id='vehicle-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy vehicle_docs_owner_upload on storage.objects for insert to authenticated with check(bucket_id='vehicle-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy vehicle_docs_reviewer_read on storage.objects for select to authenticated using(bucket_id='vehicle-documents' and exists(select 1 from public.vehicle_documents d where d.storage_path=name and public.is_reviewer_for_vehicle(d.vehicle_id)));
create policy avatars_public_read on storage.objects for select to anon,authenticated using(bucket_id='avatars');
create policy avatars_owner_upload on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy avatars_owner_update on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy avatars_owner_delete on storage.objects for delete to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- Timestamp trigger for every new public table.
do $$ declare t record; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') loop
    execute format('drop trigger if exists set_updated_at on public.%I',t.relname);
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t.relname);
  end loop;
end $$;

commit;

-- Recorded production migration 20261031203441: phase2_review_security_and_indexes
-- Phase 2 follow-up: cover every new foreign key with an index, narrow public
-- driver profile reads, and verify uploaded objects before accepting documents.
begin;

create index if not exists audit_log_actor_id_idx on public.audit_log(actor_id);
create index if not exists driver_profiles_approved_by_idx on public.driver_profiles(approved_by);
create index if not exists driver_profiles_verification_request_idx on public.driver_profiles(verification_request_id);
create index if not exists reviewer_assignments_assigned_by_idx on public.reviewer_assignments(assigned_by);
create index if not exists vehicles_approved_by_idx on public.vehicles(approved_by);
create index if not exists verification_reviews_reviewer_idx on public.verification_reviews(reviewer_id);

revoke all on public.driver_profiles from authenticated;
grant select(id,user_id,status,approved_at,created_at,updated_at) on public.driver_profiles to authenticated;
grant insert(user_id,verification_request_id) on public.driver_profiles to authenticated;

drop policy if exists vehicle_documents_owner_insert on public.vehicle_documents;
create policy vehicle_documents_owner_insert on public.vehicle_documents
for insert to authenticated
with check (
  user_id=(select auth.uid())
  and exists(select 1 from public.vehicles v where v.id=vehicle_id and v.owner_id=(select auth.uid()) and v.status in ('draft','needs_resubmission'))
  and exists(select 1 from storage.objects o where o.bucket_id='vehicle-documents' and o.name=storage_path and (storage.foldername(o.name))[1]=(select auth.uid())::text)
);

create or replace function private.capture_verification_documents()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or auth.uid() is distinct from new.user_id then
    raise exception using errcode='42501',message='Cannot submit another user verification request.';
  end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.id_front_path and (storage.foldername(o.name))[1]=new.user_id::text)
     or not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.id_back_path and (storage.foldername(o.name))[1]=new.user_id::text)
     or not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.selfie_path and (storage.foldername(o.name))[1]=new.user_id::text) then
    raise exception using errcode='22023',message='Identity images must be uploaded to the caller’s private document folder before submission.';
  end if;
  if new.user_role='driver' and (
       not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.license_front_path and (storage.foldername(o.name))[1]=new.user_id::text)
       or not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.license_back_path and (storage.foldername(o.name))[1]=new.user_id::text)
  ) then
    raise exception using errcode='22023',message='Both driving-license images must be uploaded before submission.';
  end if;
  insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path) values
    (new.user_id,new.id,'national_id_front',new.id_front_path),
    (new.user_id,new.id,'national_id_back',new.id_back_path),
    (new.user_id,new.id,'face_scan',new.selfie_path)
  on conflict(verification_request_id,document_type,version) do nothing;
  if new.license_front_path is not null then
    insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path)
    values(new.user_id,new.id,'driver_license_front',new.license_front_path)
    on conflict(verification_request_id,document_type,version) do nothing;
  end if;
  if new.license_back_path is not null then
    insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path)
    values(new.user_id,new.id,'driver_license_back',new.license_back_path)
    on conflict(verification_request_id,document_type,version) do nothing;
  end if;
  update public.verification_requests
  set id_front_path=null,id_back_path=null,selfie_path=null,license_front_path=null,license_back_path=null
  where id=new.id;
  if new.user_role='driver' then
    insert into public.driver_profiles(user_id,verification_request_id,status)
    values(new.user_id,new.id,'submitted')
    on conflict(user_id) do update set verification_request_id=excluded.verification_request_id;
  end if;
  return null;
end;
$$;
revoke all on function private.capture_verification_documents() from public,anon,authenticated;

commit;

-- Recorded production migration 20261031203730: phase3_geography_saved_routes
-- Phase 3: canonical cities, approved stops, saved routes, and legacy route links.
-- Existing trip and segment text is retained while relational references are backfilled.

begin;

create extension if not exists postgis with schema extensions;

create table if not exists public.cities (
  id uuid primary key default extensions.gen_random_uuid(),
  code text not null unique check (code ~ '^[a-z0-9_]+$'),
  name_ar text not null check (length(btrim(name_ar)) > 0),
  name_en text not null check (length(btrim(name_en)) > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create table if not exists public.approved_stops (
  id uuid primary key default extensions.gen_random_uuid(),
  city_id uuid not null references public.cities(id) on delete restrict,
  code text not null unique check (code ~ '^[a-z0-9_]+$'),
  name_ar text not null check (length(btrim(name_ar)) > 0),
  name_en text not null check (length(btrim(name_en)) > 0),
  stop_kind text not null default 'pickup_dropoff'
    check (stop_kind in ('bus_station','landmark','pickup_dropoff')),
  location extensions.geography(point, 4326) not null,
  is_active boolean not null default true,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);

create index if not exists approved_stops_city_active_idx on public.approved_stops(city_id, is_active);
create index if not exists approved_stops_location_gist_idx on public.approved_stops using gist(location);

insert into public.cities(code, name_ar, name_en) values
 ('cairo','القاهرة','Cairo'), ('giza','الجيزة','Giza'),
 ('alexandria','الإسكندرية','Alexandria'), ('mansoura','المنصورة','Mansoura'),
 ('tanta','طنطا','Tanta'), ('port_said','بورسعيد','Port Said'),
 ('suez','السويس','Suez'), ('ismailia','الإسماعيلية','Ismailia'),
 ('hurghada','الغردقة','Hurghada'), ('benha','بنها','Benha'),
 ('damanhour','دمنهور','Damanhour')
on conflict (code) do update set name_ar=excluded.name_ar, name_en=excluded.name_en;

-- Seed broadly known transport hubs / landmarks. Operators can refine exact
-- pickup access and coordinates after on-the-ground verification.
insert into public.approved_stops(city_id, code, name_ar, name_en, stop_kind, location)
select c.id, v.code, v.name_ar, v.name_en, v.stop_kind,
       extensions.st_setsrid(extensions.st_makepoint(v.longitude, v.latitude), 4326)::extensions.geography
from (values
 ('cairo','cairo_ramses','محطة رمسيس','Ramses Station','bus_station',31.2461::float8,30.0630::float8),
 ('cairo','cairo_tahrir','ميدان التحرير','Tahrir Square','landmark',31.2357,30.0444),
 ('cairo','cairo_nasr_city','مدينة نصر','Nasr City','pickup_dropoff',31.3420,30.0561),
 ('giza','giza_square','ميدان الجيزة','Giza Square','bus_station',31.2109,29.9870),
 ('giza','giza_sheikh_zayed','الشيخ زايد','Sheikh Zayed','pickup_dropoff',30.9330,30.0131),
 ('alexandria','alex_moharram_bek','محطة محرم بك','Moharram Bek Station','bus_station',29.8967,31.1839),
 ('alexandria','alex_sidi_gaber','سيدي جابر','Sidi Gaber','bus_station',29.9428,31.2194),
 ('alexandria','alex_smouha','سموحة','Smouha','pickup_dropoff',29.9553,31.2156),
 ('mansoura','mansoura_station','محطة المنصورة','Mansoura Station','bus_station',31.3785,31.0409),
 ('mansoura','mansoura_university','جامعة المنصورة','Mansoura University','landmark',31.3543,31.0418),
 ('tanta','tanta_station','محطة طنطا','Tanta Station','bus_station',30.9991,30.7865),
 ('tanta','tanta_university','جامعة طنطا','Tanta University','landmark',31.0004,30.7924),
 ('port_said','portsaid_station','محطة بورسعيد','Port Said Station','bus_station',32.3019,31.2653),
 ('port_said','portsaid_port','ميناء بورسعيد','Port Said Port','landmark',32.3030,31.2565),
 ('suez','suez_station','محطة السويس','Suez Station','bus_station',32.5498,29.9668),
 ('suez','suez_arbain','الأربعين','Arbaeen','landmark',32.5314,29.9737),
 ('ismailia','ismailia_station','محطة الإسماعيلية','Ismailia Station','bus_station',32.2715,30.5965),
 ('ismailia','ismailia_university','جامعة قناة السويس','Suez Canal University','landmark',32.2718,30.6200),
 ('hurghada','hurghada_go','موقف الغردقة','Hurghada Bus Terminal','bus_station',33.8129,27.2579),
 ('hurghada','hurghada_downtown','وسط الغردقة','Hurghada Downtown','pickup_dropoff',33.8310,27.2226),
 ('benha','benha_station','محطة بنها','Benha Station','bus_station',31.1842,30.4667),
 ('benha','benha_university','جامعة بنها','Benha University','landmark',31.1845,30.4585),
 ('damanhour','damanhour_station','محطة دمنهور','Damanhour Station','bus_station',30.4700,31.0344),
 ('damanhour','damanhour_square','ميدان الساعة بدمنهور','Damanhour Clock Square','landmark',30.4690,31.0373)
) as v(city_code,code,name_ar,name_en,stop_kind,longitude,latitude)
join public.cities c on c.code=v.city_code
on conflict (code) do update set
  city_id=excluded.city_id, name_ar=excluded.name_ar, name_en=excluded.name_en,
  stop_kind=excluded.stop_kind, location=excluded.location, is_active=true;

alter table public.trips
  add column if not exists origin_city_id uuid references public.cities(id) on delete restrict,
  add column if not exists destination_city_id uuid references public.cities(id) on delete restrict;

update public.trips t set
  origin_city_id=coalesce(t.origin_city_id, c1.id),
  destination_city_id=coalesce(t.destination_city_id, c2.id)
from public.cities c1, public.cities c2
where c1.name_ar=t.origin_city and c2.name_ar=t.destination_city
  and (t.origin_city_id is null or t.destination_city_id is null);

alter table public.trip_segments
  add column if not exists from_city_id uuid references public.cities(id) on delete restrict,
  add column if not exists to_city_id uuid references public.cities(id) on delete restrict;

update public.trip_segments s set
  from_city_id=coalesce(s.from_city_id, c1.id),
  to_city_id=coalesce(s.to_city_id, c2.id)
from public.cities c1, public.cities c2
where c1.name_ar=s.from_city and c2.name_ar=s.to_city
  and (s.from_city_id is null or s.to_city_id is null);

create index if not exists trips_route_time_idx
  on public.trips(origin_city_id, destination_city_id, departure_time)
  where status in ('upcoming','published');
create index if not exists trip_segments_city_pair_idx
  on public.trip_segments(trip_id, from_city_id, to_city_id);

create table if not exists public.saved_routes (
  id uuid primary key default extensions.gen_random_uuid(),
  rider_id uuid not null references public.profiles(id) on delete cascade,
  origin_city_id uuid not null references public.cities(id) on delete restrict,
  destination_city_id uuid not null references public.cities(id) on delete restrict,
  origin_stop_id uuid references public.approved_stops(id) on delete set null,
  destination_stop_id uuid references public.approved_stops(id) on delete set null,
  label text,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  constraint saved_routes_distinct_cities check (origin_city_id <> destination_city_id),
  constraint saved_routes_owner_route_key unique (rider_id, origin_city_id, destination_city_id)
);
create index if not exists saved_routes_rider_created_idx on public.saved_routes(rider_id, created_at desc);
create index if not exists saved_routes_origin_destination_idx on public.saved_routes(origin_city_id, destination_city_id);

alter table public.cities enable row level security;
alter table public.approved_stops enable row level security;
alter table public.saved_routes enable row level security;
revoke all on table public.cities, public.approved_stops, public.saved_routes from public, anon, authenticated;
grant select on public.cities, public.approved_stops to authenticated;
grant select, insert, update, delete on public.saved_routes to authenticated;
create policy cities_select_active on public.cities for select to authenticated using (is_active);
create policy approved_stops_select_active on public.approved_stops for select to authenticated using (is_active);
create policy saved_routes_select_own on public.saved_routes for select to authenticated using (rider_id=(select auth.uid()));
create policy saved_routes_insert_own on public.saved_routes for insert to authenticated with check (rider_id=(select auth.uid()));
create policy saved_routes_update_own on public.saved_routes for update to authenticated using (rider_id=(select auth.uid())) with check (rider_id=(select auth.uid()));
create policy saved_routes_delete_own on public.saved_routes for delete to authenticated using (rider_id=(select auth.uid()));

commit;

-- Recorded production migration 20261031203747: phase3_route_integrity_indexes
-- Phase 3 follow-up: FK indexes and stricter saved-stop/city consistency.
begin;
create index if not exists trips_destination_city_fk_idx on public.trips(destination_city_id);
create index if not exists trip_segments_from_city_fk_idx on public.trip_segments(from_city_id);
create index if not exists trip_segments_to_city_fk_idx on public.trip_segments(to_city_id);
create index if not exists saved_routes_destination_city_fk_idx on public.saved_routes(destination_city_id);
create index if not exists saved_routes_origin_stop_fk_idx on public.saved_routes(origin_stop_id);
create index if not exists saved_routes_destination_stop_fk_idx on public.saved_routes(destination_stop_id);
create unique index if not exists approved_stops_id_city_key on public.approved_stops(id, city_id);
alter table public.saved_routes
  add constraint saved_routes_origin_stop_city_fkey
    foreign key (origin_stop_id, origin_city_id)
    references public.approved_stops(id, city_id) on delete set null (origin_stop_id),
  add constraint saved_routes_destination_stop_city_fkey
    foreign key (destination_stop_id, destination_city_id)
    references public.approved_stops(id, city_id) on delete set null (destination_stop_id);
revoke insert, update on table public.saved_routes from authenticated;
grant insert (rider_id, origin_city_id, destination_city_id, origin_stop_id, destination_stop_id, label)
  on public.saved_routes to authenticated;
grant update (origin_city_id, destination_city_id, origin_stop_id, destination_stop_id, label)
  on public.saved_routes to authenticated;
commit;

-- Recorded production migration 20261031203912: phase4a_typed_statuses_and_settings
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

-- Recorded production migration 20261031204028: phase4b_booking_trip_workflows
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

-- Recorded production migration 20261031204112: phase4c_indexes_and_constraint_validation
-- Phase 4c: indexes for new foreign keys and date-first route discovery.
begin;
create index if not exists app_settings_updated_by_idx on public.app_settings(updated_by);
create index if not exists bookings_cancelled_by_idx on public.bookings(cancelled_by);
create index if not exists trips_cancelled_by_idx on public.trips(cancelled_by);
create index if not exists saved_routes_origin_stop_city_idx on public.saved_routes(origin_stop_id,origin_city_id);
create index if not exists saved_routes_destination_stop_city_idx on public.saved_routes(destination_stop_id,destination_city_id);
create index if not exists trips_departure_route_idx
  on public.trips(departure_time,origin_city_id,destination_city_id)
  where status='published';
alter table public.trips validate constraint trips_total_seats_positive;
alter table public.trips validate constraint trips_route_cities_distinct;
alter table public.trips validate constraint trips_cancellation_metadata_check;
alter table public.trip_segments validate constraint trip_segments_price_minor_nonnegative;
alter table public.bookings validate constraint bookings_total_price_minor_nonnegative;
alter table public.bookings validate constraint bookings_cancellation_metadata_check;
commit;

-- Recorded production migration 20261031204154: phase5_trip_safety_and_sharing
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

-- Recorded production migration 20261031204252: phase6a_messaging_notifications_ratings
-- Phase 6a: private booking conversations, in-app notification inbox/outbox, and post-trip ratings.
begin;

create table if not exists public.conversations (
 id uuid primary key default extensions.gen_random_uuid(),
 booking_id uuid not null unique references public.bookings(id) on delete cascade,
 trip_id uuid not null references public.trips(id) on delete cascade,
 rider_id uuid not null references public.profiles(id) on delete cascade,
 driver_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
insert into public.conversations(booking_id,trip_id,rider_id,driver_id)
select b.id,b.trip_id,b.passenger_id,t.driver_id
from public.bookings b join public.trips t on t.id=b.trip_id
on conflict(booking_id) do nothing;
alter table public.messages add column if not exists conversation_id uuid references public.conversations(id) on delete cascade;
update public.messages m set conversation_id=c.id from public.conversations c
where c.booking_id=m.booking_id and m.conversation_id is null;
alter table public.messages alter column conversation_id set not null;
create index if not exists messages_conversation_created_idx on public.messages(conversation_id,created_at);

alter table public.conversations enable row level security;
revoke all on public.conversations from public,anon,authenticated;
grant select on public.conversations to authenticated;
create policy conversations_participant_read on public.conversations for select to authenticated
using(rider_id=(select auth.uid()) or driver_id=(select auth.uid()));

drop policy if exists messages_participant_read on public.messages;
alter table public.messages enable row level security;
revoke all on public.messages from public,anon,authenticated;
grant select on public.messages to authenticated;
create policy messages_participant_read on public.messages for select to authenticated
using(exists(select 1 from public.conversations c where c.id=conversation_id
 and (c.rider_id=(select auth.uid()) or c.driver_id=(select auth.uid()))));

create or replace function public.ensure_booking_conversation()
returns trigger
language plpgsql security definer set search_path=''
as $$
begin
 if new.status='confirmed' then
  insert into public.conversations(booking_id,trip_id,rider_id,driver_id)
  select new.id,new.trip_id,new.passenger_id,t.driver_id from public.trips t where t.id=new.trip_id
  on conflict(booking_id) do nothing;
 end if;
 return new;
end $$;
revoke all on function public.ensure_booking_conversation() from public,anon,authenticated;
create trigger booking_conversation_on_confirm after insert or update of status on public.bookings
for each row execute function public.ensure_booking_conversation();

create or replace function public.send_message(p_booking_id uuid,p_content text)
returns public.messages
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_conversation public.conversations%rowtype; v_message public.messages%rowtype; v_days integer;
begin
 if v_user is null or p_content is null or length(pg_catalog.btrim(p_content))<1 or length(p_content)>4000 then
  raise exception using errcode='22023',message='Sign in and enter a message up to 4000 characters.';
 end if;
 select * into v_booking from public.bookings where id=p_booking_id for share;
 if not found or v_user not in (v_booking.passenger_id,(select t.driver_id from public.trips t where t.id=v_booking.trip_id)) then
  raise exception using errcode='42501',message='You are not part of this booking.';
 end if;
 select * into v_trip from public.trips where id=v_booking.trip_id;
 if v_booking.status not in ('confirmed','completed') or v_trip.status='cancelled' then
  raise exception using errcode='42501',message='Messaging is available only for confirmed trips.';
 end if;
 if v_trip.status='completed' then
  select (value#>>'{}')::integer into v_days from public.app_settings where key='chat_retention_days_after_trip';
  if v_trip.arrival_time is not null and pg_catalog.now()>v_trip.arrival_time+pg_catalog.make_interval(days=>coalesce(v_days,30)) then
   raise exception using errcode='42501',message='The messaging period for this trip has ended.';
  end if;
 end if;
 insert into public.conversations(booking_id,trip_id,rider_id,driver_id)
 values(v_booking.id,v_booking.trip_id,v_booking.passenger_id,v_trip.driver_id)
 on conflict(booking_id) do nothing;
 select * into v_conversation from public.conversations where booking_id=p_booking_id;
 insert into public.messages(booking_id,conversation_id,sender_id,content)
 values(v_booking.id,v_conversation.id,v_user,pg_catalog.btrim(p_content))
 returning * into v_message;
 return v_message;
end $$;
revoke all on function public.send_message(uuid,text) from public,anon,authenticated;
grant execute on function public.send_message(uuid,text) to authenticated;

create table if not exists public.notifications (
 id uuid primary key default extensions.gen_random_uuid(),
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 category text not null check(category in ('booking','trip','message','safety','support','account')),
 title jsonb not null,
 body jsonb not null,
 data jsonb not null default '{}'::jsonb,
 idempotency_key text not null unique,
 read_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists notifications_recipient_unread_idx on public.notifications(recipient_id,created_at desc) where read_at is null;
create index if not exists notifications_recipient_created_idx on public.notifications(recipient_id,created_at desc);
create table if not exists public.notification_outbox (
 id uuid primary key default extensions.gen_random_uuid(),
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 category text not null,
 event_type text not null,
 payload jsonb not null default '{}'::jsonb,
 idempotency_key text not null unique,
 available_at timestamptz not null default pg_catalog.now(),
 attempts integer not null default 0 check(attempts>=0),
 delivered_at timestamptz,
 last_error text,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists notification_outbox_pending_idx on public.notification_outbox(available_at,created_at) where delivered_at is null;
create index if not exists notification_outbox_recipient_idx on public.notification_outbox(recipient_id,created_at desc);

alter table public.notifications enable row level security;
alter table public.notification_outbox enable row level security;
revoke all on public.notifications,public.notification_outbox from public,anon,authenticated;
grant select on public.notifications to authenticated;
grant update(read_at) on public.notifications to authenticated;
create policy notifications_own_read on public.notifications for select to authenticated using(recipient_id=(select auth.uid()));
create policy notifications_own_mark_read on public.notifications for update to authenticated using(recipient_id=(select auth.uid())) with check(recipient_id=(select auth.uid()));
grant select,update on public.notification_outbox to service_role;

create trigger set_updated_at before update on public.conversations for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.notifications for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.notification_outbox for each row execute function public.set_updated_at();

create or replace function public.enqueue_notification(
 p_recipient uuid,p_category text,p_event text,p_title jsonb,p_body jsonb,p_data jsonb,p_key text
)
returns void
language plpgsql security definer set search_path=''
as $$
begin
 if p_recipient is null or p_recipient=auth.uid() and p_event='new_message' then return; end if;
 insert into public.notifications(recipient_id,category,title,body,data,idempotency_key)
 values(p_recipient,p_category,p_title,p_body,coalesce(p_data,'{}'::jsonb),p_key)
 on conflict(idempotency_key) do nothing;
 insert into public.notification_outbox(recipient_id,category,event_type,payload,idempotency_key)
 values(p_recipient,p_category,p_event,coalesce(p_data,'{}'::jsonb),p_key)
 on conflict(idempotency_key) do nothing;
end $$;
revoke all on function public.enqueue_notification(uuid,text,text,jsonb,jsonb,jsonb,text) from public,anon,authenticated;

create or replace function public.notify_booking_status_change()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v_driver uuid; v_title jsonb; v_body jsonb; v_key text;
begin
 if old.status is not distinct from new.status then return new; end if;
 select driver_id into v_driver from public.trips where id=new.trip_id;
 v_title:=case new.status when 'confirmed' then '{"ar":"تم تأكيد الحجز","en":"Booking confirmed"}'::jsonb
  when 'rejected' then '{"ar":"تعذر تأكيد الحجز","en":"Booking declined"}'::jsonb
  when 'cancelled' then '{"ar":"تم إلغاء الحجز","en":"Booking cancelled"}'::jsonb
  when 'completed' then '{"ar":"اكتملت الرحلة","en":"Trip completed"}'::jsonb
  when 'no_show' then '{"ar":"لم يتم تسجيل صعودك","en":"Boarding was not recorded"}'::jsonb
  else '{"ar":"تحديث الحجز","en":"Booking update"}'::jsonb end;
 v_body:='{"ar":"تحديث لحالة حجزك.","en":"There is an update to your booking."}'::jsonb;
 v_key:='booking:'||new.id::text||':'||new.status::text||':'||new.updated_at::text;
 perform public.enqueue_notification(new.passenger_id,'booking','booking_status',v_title,v_body,jsonb_build_object('booking_id',new.id,'status',new.status::text),v_key||':rider');
 perform public.enqueue_notification(v_driver,'booking','booking_status',v_title,v_body,jsonb_build_object('booking_id',new.id,'status',new.status::text),v_key||':driver');
 return new;
end $$;
revoke all on function public.notify_booking_status_change() from public,anon,authenticated;
create trigger booking_status_notification after update of status on public.bookings
for each row execute function public.notify_booking_status_change();

create or replace function public.notify_trip_status_change()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v_booking record; v_title jsonb; v_body jsonb; v_key text;
begin
 if old.status is not distinct from new.status then return new; end if;
 v_title:=case new.status when 'in_progress' then '{"ar":"بدأت الرحلة","en":"Trip started"}'::jsonb
  when 'completed' then '{"ar":"اكتملت الرحلة","en":"Trip completed"}'::jsonb
  when 'cancelled' then '{"ar":"تم إلغاء الرحلة","en":"Trip cancelled"}'::jsonb
  else '{"ar":"تحديث الرحلة","en":"Trip update"}'::jsonb end;
 v_body:='{"ar":"هناك تحديث على رحلتك.","en":"There is an update to your trip."}'::jsonb;
 v_key:='trip:'||new.id::text||':'||new.status::text||':'||new.updated_at::text;
 perform public.enqueue_notification(new.driver_id,'trip','trip_status',v_title,v_body,jsonb_build_object('trip_id',new.id,'status',new.status::text),v_key||':driver');
 for v_booking in select distinct passenger_id from public.bookings where trip_id=new.id loop
  perform public.enqueue_notification(v_booking.passenger_id,'trip','trip_status',v_title,v_body,jsonb_build_object('trip_id',new.id,'status',new.status::text),v_key||':'||v_booking.passenger_id::text);
 end loop;
 return new;
end $$;
revoke all on function public.notify_trip_status_change() from public,anon,authenticated;
create trigger trip_status_notification after update of status on public.trips
for each row execute function public.notify_trip_status_change();

create or replace function public.notify_new_message()
returns trigger
language plpgsql security definer set search_path=''
as $$
declare v_conversation public.conversations%rowtype; v_recipient uuid; v_key text;
begin
 select * into v_conversation from public.conversations where id=new.conversation_id;
 v_recipient:=case when new.sender_id=v_conversation.rider_id then v_conversation.driver_id else v_conversation.rider_id end;
 v_key:='message:'||new.id::text;
 perform public.enqueue_notification(v_recipient,'message','new_message',
  '{"ar":"رسالة جديدة","en":"New message"}'::jsonb,
  '{"ar":"لديك رسالة جديدة في محادثة الرحلة.","en":"You have a new trip message."}'::jsonb,
  jsonb_build_object('booking_id',new.booking_id,'conversation_id',new.conversation_id),v_key);
 return new;
end $$;
revoke all on function public.notify_new_message() from public,anon,authenticated;
create trigger new_message_notification after insert on public.messages
for each row execute function public.notify_new_message();

create table if not exists public.ratings (
 id uuid primary key default extensions.gen_random_uuid(),
 booking_id uuid not null references public.bookings(id) on delete cascade,
 reviewer_id uuid not null references public.profiles(id) on delete cascade,
 reviewee_id uuid not null references public.profiles(id) on delete cascade,
 score smallint not null check(score between 1 and 5),
 comment text check(comment is null or length(comment)<=2000),
 is_visible boolean not null default true,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint ratings_reviewer_booking_key unique(booking_id,reviewer_id),
 constraint ratings_not_self check(reviewer_id<>reviewee_id)
);
create index if not exists ratings_reviewee_created_idx on public.ratings(reviewee_id,created_at desc) where is_visible;
create index if not exists ratings_booking_idx on public.ratings(booking_id);
alter table public.ratings enable row level security;
revoke all on public.ratings from public,anon,authenticated;
grant select on public.ratings to authenticated;
create policy ratings_public_visible_read on public.ratings for select to authenticated using(is_visible);
create trigger set_updated_at before update on public.ratings for each row execute function public.set_updated_at();

create or replace function public.refresh_profile_rating()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 update public.profiles p set
  rating_count=(select count(*)::integer from public.ratings r where r.reviewee_id=new.reviewee_id and r.is_visible),
  rating_avg=coalesce((select round(avg(r.score)::numeric,2) from public.ratings r where r.reviewee_id=new.reviewee_id and r.is_visible),0)
 where p.id=new.reviewee_id;
 return new;
end $$;
revoke all on function public.refresh_profile_rating() from public,anon,authenticated;
create trigger rating_profile_summary after insert or update of is_visible,score on public.ratings for each row execute function public.refresh_profile_rating();

create or replace function public.submit_rating(p_booking_id uuid,p_score smallint,p_comment text default null)
returns public.ratings
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_reviewee uuid; v_rating public.ratings%rowtype;
begin
 if v_user is null or p_score not between 1 and 5 or p_comment is not null and length(p_comment)>2000 then raise exception using errcode='22023',message='Valid rating and sign-in are required.'; end if;
 select * into v_booking from public.bookings where id=p_booking_id and status='completed';
 if not found then raise exception using errcode='22023',message='Only a completed booking can be rated.'; end if;
 select * into v_trip from public.trips where id=v_booking.trip_id;
 if v_user=v_booking.passenger_id then v_reviewee:=v_trip.driver_id;
 elsif v_user=v_trip.driver_id then v_reviewee:=v_booking.passenger_id;
 else raise exception using errcode='42501',message='Only trip participants can leave a rating.'; end if;
 insert into public.ratings(booking_id,reviewer_id,reviewee_id,score,comment)
 values(p_booking_id,v_user,v_reviewee,p_score,nullif(pg_catalog.btrim(p_comment),''))
 returning * into v_rating;
 return v_rating;
end $$;
revoke all on function public.submit_rating(uuid,smallint,text) from public,anon,authenticated;
grant execute on function public.submit_rating(uuid,smallint,text) to authenticated;

do $$ begin
 if exists(select 1 from pg_publication where pubname='supabase_realtime')
  and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='messages') then
  execute 'alter publication supabase_realtime add table public.messages';
 end if;
end $$;

commit;

-- Recorded production migration 20261031204422: phase6b_reports_support
-- Phase 6b: user reports, private report evidence, and support center.
begin;

do $$ begin create type public.emergency_incident_status as enum ('open','acknowledged','resolved'); exception when duplicate_object then null; end $$;
alter table public.emergency_incidents drop constraint if exists emergency_incidents_resolution_check;
alter table public.emergency_incidents drop constraint if exists emergency_incidents_status_check;
alter table public.emergency_incidents alter column status drop default;
alter table public.emergency_incidents alter column status type public.emergency_incident_status using status::public.emergency_incident_status;
alter table public.emergency_incidents alter column status set default 'open'::public.emergency_incident_status;
alter table public.emergency_incidents add constraint emergency_incidents_resolution_check
 check ((status='resolved')=(resolved_at is not null)) not valid;
alter table public.emergency_incidents validate constraint emergency_incidents_resolution_check;

do $$ begin create type public.report_status as enum ('open','under_review','resolved','dismissed'); exception when duplicate_object then null; end $$;
do $$ begin create type public.support_ticket_status as enum ('open','in_progress','resolved','closed'); exception when duplicate_object then null; end $$;

alter table public.allowed_status_transitions drop constraint if exists allowed_status_transitions_entity_type_check;
alter table public.allowed_status_transitions add constraint allowed_status_transitions_entity_type_check
 check(entity_type in ('verification','driver_profile','vehicle','trip','booking','deletion','emergency_incident','report','support_ticket'));

create table if not exists public.reports (
 id uuid primary key default extensions.gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete restrict,
 target_user_id uuid references public.profiles(id) on delete set null,
 trip_id uuid references public.trips(id) on delete set null,
 booking_id uuid references public.bookings(id) on delete set null,
 category text not null check(category in ('safety','harassment','fraud','trip_quality','identity','other')),
 description text not null check(length(pg_catalog.btrim(description)) between 10 and 5000),
 status public.report_status not null default 'open',
 resolution_note text,
 resolved_by uuid references public.profiles(id) on delete set null,
 resolved_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint reports_resolution_metadata_check check ((status in ('resolved','dismissed'))=(resolved_at is not null))
);
create index if not exists reports_reporter_created_idx on public.reports(reporter_id,created_at desc);
create index if not exists reports_target_created_idx on public.reports(target_user_id,created_at desc);
create index if not exists reports_trip_created_idx on public.reports(trip_id,created_at desc);
create index if not exists reports_status_created_idx on public.reports(status,created_at);

create table if not exists public.report_assignments (
 id uuid primary key default extensions.gen_random_uuid(),
 report_id uuid not null references public.reports(id) on delete cascade,
 reviewer_id uuid not null references public.profiles(id) on delete restrict,
 assigned_by uuid references public.profiles(id) on delete set null,
 assigned_at timestamptz not null default pg_catalog.now(),
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint report_assignments_report_reviewer_key unique(report_id,reviewer_id)
);
create index if not exists report_assignments_reviewer_idx on public.report_assignments(reviewer_id,assigned_at desc);
create index if not exists report_assignments_assigned_by_idx on public.report_assignments(assigned_by);

create table if not exists public.report_evidence (
 id uuid primary key default extensions.gen_random_uuid(),
 report_id uuid not null references public.reports(id) on delete cascade,
 uploaded_by uuid not null references public.profiles(id) on delete restrict,
 object_path text not null unique,
 mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp','video/mp4')),
 file_size_bytes bigint not null check(file_size_bytes between 1 and 10485760),
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint report_evidence_path_owner check(object_path like uploaded_by::text||'/'||report_id::text||'/%')
);
create index if not exists report_evidence_report_idx on public.report_evidence(report_id,created_at);

create table if not exists public.support_tickets (
 id uuid primary key default extensions.gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 category text not null check(category in ('account','verification','booking','trip','payment','safety','other')),
 subject text not null check(length(pg_catalog.btrim(subject)) between 3 and 160),
 description text not null check(length(pg_catalog.btrim(description)) between 10 and 5000),
 status public.support_ticket_status not null default 'open',
 assigned_to uuid references public.profiles(id) on delete set null,
 closed_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists support_tickets_user_created_idx on public.support_tickets(user_id,created_at desc);
create index if not exists support_tickets_status_created_idx on public.support_tickets(status,created_at);
create index if not exists support_tickets_assigned_idx on public.support_tickets(assigned_to,status);

create table if not exists public.support_messages (
 id uuid primary key default extensions.gen_random_uuid(),
 ticket_id uuid not null references public.support_tickets(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(length(pg_catalog.btrim(body)) between 1 and 5000),
 is_internal boolean not null default false,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists support_messages_ticket_created_idx on public.support_messages(ticket_id,created_at);
create index if not exists support_messages_sender_idx on public.support_messages(sender_id);

do $$ declare t text; begin
 foreach t in array array['reports','report_assignments','report_evidence','support_tickets','support_messages'] loop
  execute pg_catalog.format('alter table public.%I enable row level security',t);
  execute pg_catalog.format('revoke all on table public.%I from public,anon,authenticated',t);
 end loop;
end $$;
create trigger set_updated_at before update on public.reports for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.report_assignments for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.support_tickets for each row execute function public.set_updated_at();

grant select on public.reports to authenticated;
create policy reports_participant_read on public.reports for select to authenticated using(
 reporter_id=(select auth.uid()) or public.has_role('admin'::public.app_role)
 or exists(select 1 from public.report_assignments a where a.report_id=reports.id and a.reviewer_id=(select auth.uid()))
);
grant select on public.report_assignments to authenticated;
create policy report_assignments_assigned_read on public.report_assignments for select to authenticated using(reviewer_id=(select auth.uid()) or public.has_role('admin'::public.app_role));
grant select on public.report_evidence to authenticated;
create policy report_evidence_report_read on public.report_evidence for select to authenticated using(
 exists(select 1 from public.reports r where r.id=report_id and (
  r.reporter_id=(select auth.uid()) or public.has_role('admin'::public.app_role)
  or exists(select 1 from public.report_assignments a where a.report_id=r.id and a.reviewer_id=(select auth.uid()))
 ))
);

grant select,insert on public.support_tickets to authenticated;
create policy support_tickets_owner_or_staff_read on public.support_tickets for select to authenticated using(
 user_id=(select auth.uid()) or public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role)
);
create policy support_tickets_owner_insert on public.support_tickets for insert to authenticated with check(
 user_id=(select auth.uid()) and status='open' and assigned_to is null and closed_at is null
);
grant select on public.support_messages to authenticated;
create policy support_messages_owner_or_staff_read on public.support_messages for select to authenticated using(
 exists(select 1 from public.support_tickets t where t.id=ticket_id and (
  (t.user_id=(select auth.uid()) and is_internal=false)
  or public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role)
 ))
);

create or replace function public.create_support_ticket(p_category text,p_subject text,p_description text)
returns public.support_tickets
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_ticket public.support_tickets%rowtype;
begin
 if v_user is null then raise exception using errcode='42501',message='Login required.'; end if;
 insert into public.support_tickets(user_id,category,subject,description)
 values(v_user,p_category,pg_catalog.btrim(p_subject),pg_catalog.btrim(p_description)) returning * into v_ticket;
 insert into public.support_messages(ticket_id,sender_id,body,is_internal)
 values(v_ticket.id,v_user,pg_catalog.btrim(p_description),false);
 return v_ticket;
end $$;
revoke all on function public.create_support_ticket(text,text,text) from public,anon,authenticated;
grant execute on function public.create_support_ticket(text,text,text) to authenticated;

create or replace function public.add_support_message(p_ticket_id uuid,p_body text,p_is_internal boolean default false)
returns public.support_messages
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_ticket public.support_tickets%rowtype; v_message public.support_messages%rowtype; v_staff boolean;
begin
 if v_user is null or p_body is null or length(pg_catalog.btrim(p_body)) not between 1 and 5000 then raise exception using errcode='22023',message='Sign in and provide a valid message.'; end if;
 v_staff:=public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role);
 select * into v_ticket from public.support_tickets where id=p_ticket_id for update;
 if not found or (v_ticket.user_id<>v_user and not v_staff) then raise exception using errcode='42501',message='Ticket not found or not accessible.'; end if;
 if p_is_internal and not v_staff then raise exception using errcode='42501',message='Only support staff can create internal notes.'; end if;
 if v_ticket.status in ('resolved','closed') and not v_staff then raise exception using errcode='22023',message='This ticket is closed.'; end if;
 insert into public.support_messages(ticket_id,sender_id,body,is_internal)
 values(p_ticket_id,v_user,pg_catalog.btrim(p_body),p_is_internal) returning * into v_message;
 if v_ticket.status='open' and v_staff then update public.support_tickets set status='in_progress',assigned_to=coalesce(assigned_to,v_user) where id=p_ticket_id; end if;
 return v_message;
end $$;
revoke all on function public.add_support_message(uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.add_support_message(uuid,text,boolean) to authenticated;

create or replace function public.close_own_support_ticket(p_ticket_id uuid)
returns boolean
language plpgsql security definer set search_path=''
as $$
begin
 update public.support_tickets set status='closed',closed_at=pg_catalog.now()
 where id=p_ticket_id and user_id=auth.uid() and status in ('open','in_progress');
 return found;
end $$;
revoke all on function public.close_own_support_ticket(uuid) from public,anon,authenticated;
grant execute on function public.close_own_support_ticket(uuid) to authenticated;

insert into public.allowed_status_transitions(entity_type,from_status,to_status,actor_role)
select v.entity_type,v.from_status,v.to_status,v.actor_role::public.app_role
from (values
 ('emergency_incident','open','acknowledged','reviewer'),
 ('emergency_incident','open','resolved','admin'),
 ('emergency_incident','acknowledged','resolved','admin'),
 ('report','open','under_review','reviewer'),
 ('report','open','resolved','admin'),
 ('report','open','dismissed','admin'),
 ('report','under_review','resolved','admin'),
 ('report','under_review','dismissed','admin'),
 ('report','under_review','open','reviewer'),
 ('support_ticket','open','in_progress','reviewer'),
 ('support_ticket','open','closed','rider'),
 ('support_ticket','in_progress','resolved','reviewer'),
 ('support_ticket','in_progress','closed','rider'),
 ('support_ticket','resolved','closed','rider'),
 ('support_ticket','resolved','in_progress','reviewer')
) v(entity_type,from_status,to_status,actor_role)
where not exists(select 1 from public.allowed_status_transitions a where a.entity_type=v.entity_type
 and a.from_status=v.from_status and a.to_status=v.to_status and a.actor_role is not distinct from v.actor_role::public.app_role);

create trigger emergency_incidents_workflow_guard before update of status on public.emergency_incidents for each row execute function public.enforce_workflow_transition('emergency_incident');
create trigger reports_workflow_guard before update of status on public.reports for each row execute function public.enforce_workflow_transition('report');
create trigger reports_workflow_audit after update of status on public.reports for each row execute function public.log_workflow_transition('report');
create trigger support_tickets_workflow_guard before update of status on public.support_tickets for each row execute function public.enforce_workflow_transition('support_ticket');

-- Supabase Storage bucket creation/configuration via SQL.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('report-evidence','report-evidence',false,10485760,array['image/jpeg','image/png','image/webp','video/mp4'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists report_evidence_owner_upload on storage.objects;
create policy report_evidence_owner_upload on storage.objects for insert to authenticated with check(
 bucket_id='report-evidence' and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists(select 1 from public.reports r where r.id::text=(storage.foldername(name))[2] and r.reporter_id=(select auth.uid()) and r.status='open')
);
drop policy if exists report_evidence_participant_read on storage.objects;
create policy report_evidence_participant_read on storage.objects for select to authenticated using(
 bucket_id='report-evidence' and exists(
  select 1 from public.report_evidence e join public.reports r on r.id=e.report_id
  where e.object_path=name and (r.reporter_id=(select auth.uid()) or public.has_role('admin'::public.app_role)
   or exists(select 1 from public.report_assignments a where a.report_id=r.id and a.reviewer_id=(select auth.uid())))
 )
);
drop policy if exists report_evidence_owner_delete on storage.objects;
create policy report_evidence_owner_delete on storage.objects for delete to authenticated using(
 bucket_id='report-evidence' and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists(select 1 from public.report_evidence e join public.reports r on r.id=e.report_id where e.object_path=name and r.reporter_id=(select auth.uid()) and r.status='open')
);

create or replace function public.create_report(
 p_category text,p_description text,p_trip_id uuid default null,p_booking_id uuid default null,p_target_user_id uuid default null
)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_trip_id uuid:=p_trip_id; v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_id uuid;
begin
 if v_user is null or p_category not in ('safety','harassment','fraud','trip_quality','identity','other')
   or p_description is null or length(pg_catalog.btrim(p_description)) not between 10 and 5000 then
  raise exception using errcode='22023',message='Valid report details and sign-in are required.';
 end if;
 if p_booking_id is not null then
  select * into v_booking from public.bookings where id=p_booking_id;
  if not found then raise exception using errcode='P0002',message='Booking not found.'; end if;
  v_trip_id:=v_booking.trip_id;
 end if;
 if v_trip_id is not null then
  select * into v_trip from public.trips where id=v_trip_id;
  if not found then raise exception using errcode='P0002',message='Trip not found.'; end if;
  if v_user<>v_trip.driver_id and not exists(select 1 from public.bookings b where b.trip_id=v_trip_id and b.passenger_id=v_user) then
   raise exception using errcode='42501',message='Only a trip participant can report this trip.';
  end if;
 end if;
 if p_target_user_id is not null and (v_trip_id is null or
   (p_target_user_id<>v_trip.driver_id and not exists(select 1 from public.bookings b where b.trip_id=v_trip_id and b.passenger_id=p_target_user_id))) then
  raise exception using errcode='42501',message='Reported user must be part of the related trip.';
 end if;
 insert into public.reports(reporter_id,target_user_id,trip_id,booking_id,category,description)
 values(v_user,p_target_user_id,v_trip_id,p_booking_id,p_category,pg_catalog.btrim(p_description))
 returning id into v_id;
 return v_id;
end $$;
revoke all on function public.create_report(text,text,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_report(text,text,uuid,uuid,uuid) to authenticated;

create or replace function public.add_report_evidence(p_report_id uuid,p_object_path text,p_mime_type text,p_file_size_bytes bigint)
returns public.report_evidence
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_row public.report_evidence%rowtype;
begin
 if v_user is null or p_object_path not like v_user::text||'/'||p_report_id::text||'/%' then raise exception using errcode='42501',message='Evidence path must belong to this report and user.'; end if;
 if not exists(select 1 from public.reports r where r.id=p_report_id and r.reporter_id=v_user and r.status='open')
  or not exists(select 1 from storage.objects o where o.bucket_id='report-evidence' and o.name=p_object_path) then
  raise exception using errcode='42501',message='Report or uploaded evidence not found.';
 end if;
 insert into public.report_evidence(report_id,uploaded_by,object_path,mime_type,file_size_bytes)
 values(p_report_id,v_user,p_object_path,p_mime_type,p_file_size_bytes) returning * into v_row;
 return v_row;
end $$;
revoke all on function public.add_report_evidence(uuid,text,text,bigint) from public,anon,authenticated;
grant execute on function public.add_report_evidence(uuid,text,text,bigint) to authenticated;

commit;

-- Recorded production migration 20261031204712: phase7_admin_payments_retention
-- Phase 7: simulated cash ledger, platform administration, organizations, and retention work queues.
begin;

do $$ begin create type public.simulated_payment_status as enum ('cash_due','cash_received','refund_requested','refund_simulated','voided'); exception when duplicate_object then null; end $$;
do $$ begin create type public.refund_request_status as enum ('open','approved','rejected','simulated'); exception when duplicate_object then null; end $$;

alter table public.emergency_incidents
 add column if not exists resolved_by uuid references public.profiles(id) on delete set null,
 add column if not exists resolution_note text;
create index if not exists emergency_incidents_resolved_by_idx on public.emergency_incidents(resolved_by);

alter table public.allowed_status_transitions drop constraint if exists allowed_status_transitions_entity_type_check;
alter table public.allowed_status_transitions add constraint allowed_status_transitions_entity_type_check
 check(entity_type in ('verification','driver_profile','vehicle','trip','booking','deletion','emergency_incident','report','support_ticket','payment','refund_request'));

insert into public.allowed_status_transitions(entity_type,from_status,to_status,actor_role)
select v.entity_type,v.from_status,v.to_status,v.actor_role::public.app_role
from (values
 ('payment','cash_due','cash_received','driver'),
 ('payment','cash_due','voided',null),
 ('payment','cash_received','refund_requested','rider'),
 ('payment','refund_requested','refund_simulated','admin'),
 ('payment','refund_requested','cash_received','admin'),
 ('refund_request','open','approved','admin'),
 ('refund_request','open','rejected','admin'),
 ('refund_request','approved','simulated','admin'),
 ('deletion','requested','processing','admin'),
 ('deletion','requested','rejected','admin'),
 ('deletion','processing','completed','admin'),
 ('deletion','processing','rejected','admin')
) v(entity_type,from_status,to_status,actor_role)
where not exists(select 1 from public.allowed_status_transitions a where a.entity_type=v.entity_type
 and a.from_status=v.from_status and a.to_status=v.to_status and a.actor_role is not distinct from v.actor_role::public.app_role);

create table if not exists public.simulated_payments (
 id uuid primary key default extensions.gen_random_uuid(),
 booking_id uuid not null unique references public.bookings(id) on delete restrict,
 payer_id uuid not null references public.profiles(id) on delete restrict,
 payee_id uuid not null references public.profiles(id) on delete restrict,
 amount_minor bigint not null check(amount_minor>=0),
 currency char(3) not null default 'EGP' check(currency='EGP'),
 status public.simulated_payment_status not null default 'cash_due',
 cash_reported_by uuid references public.profiles(id) on delete set null,
 cash_reported_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint simulated_payments_different_participants check(payer_id<>payee_id),
 constraint simulated_payments_cash_metadata_check check((status in ('cash_received','refund_requested','refund_simulated'))=(cash_reported_at is not null and cash_reported_by is not null))
);
create index if not exists simulated_payments_payer_created_idx on public.simulated_payments(payer_id,created_at desc);
create index if not exists simulated_payments_payee_created_idx on public.simulated_payments(payee_id,created_at desc);
create index if not exists simulated_payments_booking_idx on public.simulated_payments(booking_id);

create table if not exists public.refund_requests (
 id uuid primary key default extensions.gen_random_uuid(),
 simulated_payment_id uuid not null references public.simulated_payments(id) on delete restrict,
 requester_id uuid not null references public.profiles(id) on delete restrict,
 amount_minor bigint not null check(amount_minor>=0),
 reason text not null check(length(pg_catalog.btrim(reason)) between 5 and 2000),
 status public.refund_request_status not null default 'open',
 decision_note text,
 decided_by uuid references public.profiles(id) on delete set null,
 decided_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint refund_requests_decision_metadata_check check((status in ('approved','rejected','simulated'))=(decided_at is not null))
);
create index if not exists refund_requests_payment_idx on public.refund_requests(simulated_payment_id);
create index if not exists refund_requests_requester_idx on public.refund_requests(requester_id,created_at desc);
create index if not exists refund_requests_status_idx on public.refund_requests(status,created_at);

create table if not exists public.simulated_payment_events (
 id uuid primary key default extensions.gen_random_uuid(),
 simulated_payment_id uuid not null references public.simulated_payments(id) on delete restrict,
 actor_id uuid references public.profiles(id) on delete set null,
 event_type text not null check(event_type in ('cash_due_created','cash_received_reported','refund_requested','refund_approved','refund_rejected','refund_simulated','payment_voided')),
 details jsonb not null default '{}'::jsonb,
 occurred_at timestamptz not null default pg_catalog.now(),
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists simulated_payment_events_payment_time_idx on public.simulated_payment_events(simulated_payment_id,occurred_at);
create index if not exists simulated_payment_events_actor_idx on public.simulated_payment_events(actor_id);

create table if not exists public.organizations (
 id uuid primary key default extensions.gen_random_uuid(),
 name text not null check(length(pg_catalog.btrim(name)) between 2 and 160),
 organization_type text not null check(organization_type in ('transport_operator','university','employer','other')),
 status text not null default 'active' check(status in ('active','suspended','closed')),
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists organizations_status_created_idx on public.organizations(status,created_at);

create table if not exists public.organization_members (
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 member_role text not null check(member_role in ('owner','dispatcher','viewer')),
 invited_by uuid references public.profiles(id) on delete set null,
 joined_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint organization_members_org_user_key unique(organization_id,user_id)
);
create index if not exists organization_members_user_idx on public.organization_members(user_id,organization_id);
create index if not exists organization_members_inviter_idx on public.organization_members(invited_by);

create table if not exists public.admin_actions (
 id uuid primary key default extensions.gen_random_uuid(),
 actor_id uuid references public.profiles(id) on delete set null,
 action text not null check(length(pg_catalog.btrim(action)) between 2 and 120),
 target_type text,
 target_id uuid,
 details jsonb not null default '{}'::jsonb,
 occurred_at timestamptz not null default pg_catalog.now(),
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists admin_actions_actor_time_idx on public.admin_actions(actor_id,occurred_at desc);
create index if not exists admin_actions_target_idx on public.admin_actions(target_type,target_id,occurred_at desc);

create table if not exists public.account_deletion_jobs (
 id uuid primary key default extensions.gen_random_uuid(),
 request_id uuid not null unique,
 user_id uuid not null,
 operation text not null check(operation in ('disable_auth_user','delete_auth_user')),
 status text not null default 'pending' check(status in ('pending','processing','completed','failed')),
 attempts integer not null default 0 check(attempts>=0),
 available_at timestamptz not null default pg_catalog.now(),
 last_error text,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists account_deletion_jobs_pending_idx on public.account_deletion_jobs(available_at,created_at) where status in ('pending','failed');

create table if not exists public.storage_deletion_jobs (
 id uuid primary key default extensions.gen_random_uuid(),
 bucket_id text not null,
 object_path text not null,
 delete_after timestamptz not null,
 status text not null default 'pending' check(status in ('pending','processing','completed','failed')),
 attempts integer not null default 0 check(attempts>=0),
 last_error text,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint storage_deletion_object_key unique(bucket_id,object_path)
);
create index if not exists storage_deletion_jobs_due_idx on public.storage_deletion_jobs(delete_after,created_at) where status in ('pending','failed');

do $$ declare t text; begin
 foreach t in array array['simulated_payments','refund_requests','simulated_payment_events','organizations','organization_members','admin_actions','account_deletion_jobs','storage_deletion_jobs'] loop
  execute pg_catalog.format('alter table public.%I enable row level security',t);
  execute pg_catalog.format('revoke all on table public.%I from public,anon,authenticated',t);
  execute pg_catalog.format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t);
 end loop;
end $$;

grant select on public.simulated_payments to authenticated;
create policy simulated_payment_participant_read on public.simulated_payments for select to authenticated using(payer_id=(select auth.uid()) or payee_id=(select auth.uid()) or public.has_role('admin'::public.app_role));
grant select on public.refund_requests to authenticated;
create policy refund_request_participant_read on public.refund_requests for select to authenticated using(
 requester_id=(select auth.uid()) or exists(select 1 from public.simulated_payments p where p.id=simulated_payment_id and p.payee_id=(select auth.uid())) or public.has_role('admin'::public.app_role)
);
grant select on public.simulated_payment_events to authenticated;
create policy simulated_payment_events_participant_read on public.simulated_payment_events for select to authenticated using(
 exists(select 1 from public.simulated_payments p where p.id=simulated_payment_id and (p.payer_id=(select auth.uid()) or p.payee_id=(select auth.uid()) or public.has_role('admin'::public.app_role)))
);

grant select on public.organizations,public.organization_members to authenticated;
create policy organization_membership_self_read on public.organization_members for select to authenticated using(user_id=(select auth.uid()) or public.has_role('admin'::public.app_role));
create policy organizations_member_read on public.organizations for select to authenticated using(
 public.has_role('admin'::public.app_role) or exists(select 1 from public.organization_members m where m.organization_id=id and m.user_id=(select auth.uid()))
);
grant select on public.admin_actions to authenticated;
create policy admin_actions_admin_read on public.admin_actions for select to authenticated using(public.has_role('admin'::public.app_role));

grant select,update on public.account_deletion_jobs,public.storage_deletion_jobs to service_role;
revoke insert on public.account_deletion_requests from authenticated;

create trigger simulated_payments_workflow_guard before update of status on public.simulated_payments
 for each row execute function public.enforce_workflow_transition('payment');
create trigger simulated_payments_workflow_audit after update of status on public.simulated_payments
 for each row execute function public.log_workflow_transition('payment');
create trigger refund_requests_workflow_guard before update of status on public.refund_requests
 for each row execute function public.enforce_workflow_transition('refund_request');
create trigger refund_requests_workflow_audit after update of status on public.refund_requests
 for each row execute function public.log_workflow_transition('refund_request');
create trigger account_deletion_workflow_guard before update of status on public.account_deletion_requests
 for each row execute function public.enforce_workflow_transition('deletion');
create trigger account_deletion_workflow_audit after update of status on public.account_deletion_requests
 for each row execute function public.log_workflow_transition('account_deletion_request');

insert into public.simulated_payments(booking_id,payer_id,payee_id,amount_minor)
select b.id,b.passenger_id,t.driver_id,b.total_price_minor
from public.bookings b join public.trips t on t.id=b.trip_id
where b.status='confirmed'
on conflict(booking_id) do nothing;
insert into public.simulated_payment_events(simulated_payment_id,event_type,details)
select p.id,'cash_due_created',jsonb_build_object('mode','cash_simulated')
from public.simulated_payments p
on conflict do nothing;

create or replace function public.create_cash_due_for_confirmed_booking()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_driver uuid;
begin
 if new.status='confirmed' and (tg_op='INSERT' or old.status is distinct from new.status) then
  select driver_id into v_driver from public.trips where id=new.trip_id;
  insert into public.simulated_payments(booking_id,payer_id,payee_id,amount_minor)
  values(new.id,new.passenger_id,v_driver,new.total_price_minor) on conflict(booking_id) do nothing;
 elsif new.status='cancelled' and old.status is distinct from new.status then
  update public.simulated_payments set status='voided' where booking_id=new.id and status='cash_due';
 end if;
 return new;
end $$;
revoke all on function public.create_cash_due_for_confirmed_booking() from public,anon,authenticated;
create trigger booking_cash_payment_sync after insert or update of status on public.bookings
 for each row execute function public.create_cash_due_for_confirmed_booking();

create or replace function public.log_simulated_payment_event()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_event text;
begin
 if tg_op='INSERT' then v_event:='cash_due_created';
 else
  if old.status is not distinct from new.status then return new; end if;
  v_event:=case new.status when 'cash_received' then 'cash_received_reported' when 'refund_requested' then 'refund_requested'
   when 'refund_simulated' then 'refund_simulated' when 'voided' then 'payment_voided' else 'cash_due_created' end;
 end if;
 insert into public.simulated_payment_events(simulated_payment_id,actor_id,event_type,details)
 values(new.id,auth.uid(),v_event,jsonb_build_object('status',new.status::text,'amount_minor',new.amount_minor));
 return new;
end $$;
revoke all on function public.log_simulated_payment_event() from public,anon,authenticated;
create trigger simulated_payment_event_log after insert or update of status on public.simulated_payments
 for each row execute function public.log_simulated_payment_event();

create or replace function public.audit_admin_action(p_action text,p_target_type text,p_target_id uuid,p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 insert into public.admin_actions(actor_id,action,target_type,target_id,details)
 values(auth.uid(),p_action,p_target_type,p_target_id,coalesce(p_details,'{}'::jsonb));
 insert into public.audit_log(actor_id,action,entity_type,entity_id,occurred_at,metadata)
 values(auth.uid(),p_action,p_target_type,p_target_id,pg_catalog.now(),coalesce(p_details,'{}'::jsonb));
end $$;
revoke all on function public.audit_admin_action(text,text,uuid,jsonb) from public,anon,authenticated;

create or replace function public.assign_user_role(p_user_id uuid,p_role public.app_role,p_grant boolean)
returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id) then raise exception using errcode='P0002',message='User not found.'; end if;
 if p_role='rider' and not p_grant then raise exception using errcode='22023',message='Every account retains the rider role.'; end if;
 if p_role='driver' and p_grant and not exists(select 1 from public.driver_profiles where user_id=p_user_id and status='approved') then
  raise exception using errcode='22023',message='Only approved drivers can be assigned the driver role.';
 end if;
 if p_role='admin' and not p_grant and (select count(*) from public.user_roles where role='admin')<=1 then
  raise exception using errcode='22023',message='The last administrator cannot be removed.';
 end if;
 if p_grant then
  insert into public.user_roles(user_id,role,assigned_by) values(p_user_id,p_role,auth.uid()) on conflict(user_id,role) do nothing;
 else delete from public.user_roles where user_id=p_user_id and role=p_role;
 end if;
 perform public.audit_admin_action(case when p_grant then 'role_granted' else 'role_revoked' end,'user',p_user_id,jsonb_build_object('role',p_role::text));
 return true;
end $$;
revoke all on function public.assign_user_role(uuid,public.app_role,boolean) from public,anon,authenticated;
grant execute on function public.assign_user_role(uuid,public.app_role,boolean) to authenticated;

create or replace function public.set_app_setting(p_key text,p_value jsonb)
returns public.app_settings language plpgsql security definer set search_path=''
as $$
declare v_row public.app_settings%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 select * into v_row from public.app_settings where key=p_key for update;
 if not found then raise exception using errcode='P0002',message='Setting not found.'; end if;
 if jsonb_typeof(v_row.value)<>jsonb_typeof(p_value) then raise exception using errcode='22023',message='Setting value type cannot change.'; end if;
 update public.app_settings set value=p_value,updated_by=auth.uid() where key=p_key returning * into v_row;
 perform public.audit_admin_action('setting_updated','app_setting',null,jsonb_build_object('key',p_key));
 return v_row;
end $$;
revoke all on function public.set_app_setting(text,jsonb) from public,anon,authenticated;
grant execute on function public.set_app_setting(text,jsonb) to authenticated;

create or replace function public.assign_report_reviewer(p_report_id uuid,p_reviewer_id uuid)
returns public.report_assignments language plpgsql security definer set search_path=''
as $$
declare v_row public.report_assignments%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 if not exists(select 1 from public.user_roles where user_id=p_reviewer_id and role='reviewer') then raise exception using errcode='22023',message='Selected account is not a reviewer.'; end if;
 insert into public.report_assignments(report_id,reviewer_id,assigned_by) values(p_report_id,p_reviewer_id,auth.uid())
 on conflict(report_id,reviewer_id) do update set assigned_by=excluded.assigned_by returning * into v_row;
 update public.reports set status='under_review' where id=p_report_id and status='open';
 perform public.audit_admin_action('report_reviewer_assigned','report',p_report_id,jsonb_build_object('reviewer_id',p_reviewer_id));
 return v_row;
end $$;
revoke all on function public.assign_report_reviewer(uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_report_reviewer(uuid,uuid) to authenticated;

create or replace function public.resolve_report(p_report_id uuid,p_status public.report_status,p_note text default null)
returns public.reports language plpgsql security definer set search_path=''
as $$
declare v_report public.reports%rowtype; v_actor uuid:=auth.uid(); v_admin boolean:=public.has_role('admin'::public.app_role);
begin
 if v_actor is null or p_status not in ('under_review','resolved','dismissed') then raise exception using errcode='22023',message='Invalid review decision.'; end if;
 select * into v_report from public.reports where id=p_report_id for update;
 if not found then raise exception using errcode='P0002',message='Report not found.'; end if;
 if not v_admin and (not public.has_role('reviewer'::public.app_role) or not exists(select 1 from public.report_assignments a where a.report_id=p_report_id and a.reviewer_id=v_actor)) then
  raise exception using errcode='42501',message='Assigned reviewer or administrator role required.';
 end if;
 if p_status in ('resolved','dismissed') and not v_admin then raise exception using errcode='42501',message='Only administrators can close a report.'; end if;
 update public.reports set status=p_status,resolution_note=nullif(pg_catalog.btrim(p_note),''),
  resolved_by=case when p_status in ('resolved','dismissed') then v_actor else null end,
  resolved_at=case when p_status in ('resolved','dismissed') then pg_catalog.now() else null end
 where id=p_report_id returning * into v_report;
 if v_admin then perform public.audit_admin_action('report_decided','report',p_report_id,jsonb_build_object('status',p_status::text)); end if;
 return v_report;
end $$;
revoke all on function public.resolve_report(uuid,public.report_status,text) from public,anon,authenticated;
grant execute on function public.resolve_report(uuid,public.report_status,text) to authenticated;

create or replace function public.resolve_emergency_incident(p_incident_id uuid,p_status public.emergency_incident_status,p_note text default null)
returns public.emergency_incidents language plpgsql security definer set search_path=''
as $$
declare v_row public.emergency_incidents%rowtype; v_actor uuid:=auth.uid();
begin
 if v_actor is null or not (public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role))
  or p_status not in ('acknowledged','resolved') then raise exception using errcode='42501',message='Support staff and a valid status are required.'; end if;
 select * into v_row from public.emergency_incidents where id=p_incident_id for update;
 if not found then raise exception using errcode='P0002',message='Incident not found.'; end if;
 if p_status='resolved' and not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Only an administrator can resolve an incident.'; end if;
 update public.emergency_incidents set status=p_status,resolved_at=case when p_status='resolved' then pg_catalog.now() else null end,
  resolved_by=case when p_status='resolved' then v_actor else null end,
  resolution_note=nullif(pg_catalog.btrim(p_note),'') where id=p_incident_id returning * into v_row;
 if public.has_role('admin'::public.app_role) then perform public.audit_admin_action('emergency_incident_decided','emergency_incident',p_incident_id,jsonb_build_object('status',p_status::text)); end if;
 return v_row;
end $$;
revoke all on function public.resolve_emergency_incident(uuid,public.emergency_incident_status,text) from public,anon,authenticated;
grant execute on function public.resolve_emergency_incident(uuid,public.emergency_incident_status,text) to authenticated;

create or replace function public.resolve_support_ticket(p_ticket_id uuid,p_note text default null)
returns public.support_tickets language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_row public.support_tickets%rowtype;
begin
 if v_user is null or not (public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role)) then raise exception using errcode='42501',message='Support staff role required.'; end if;
 update public.support_tickets set status='resolved',assigned_to=coalesce(assigned_to,v_user),closed_at=pg_catalog.now()
 where id=p_ticket_id and status in ('open','in_progress') returning * into v_row;
 if not found then raise exception using errcode='P0002',message='Open support ticket not found.'; end if;
 if public.has_role('admin'::public.app_role) then perform public.audit_admin_action('support_ticket_resolved','support_ticket',p_ticket_id,jsonb_build_object('note',nullif(pg_catalog.btrim(p_note),''))); end if;
 return v_row;
end $$;
revoke all on function public.resolve_support_ticket(uuid,text) from public,anon,authenticated;
grant execute on function public.resolve_support_ticket(uuid,text) to authenticated;

create or replace function public.create_organization(p_name text,p_type text,p_owner_id uuid)
returns public.organizations language plpgsql security definer set search_path=''
as $$
declare v_org public.organizations%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 insert into public.organizations(name,organization_type,created_by) values(pg_catalog.btrim(p_name),p_type,auth.uid()) returning * into v_org;
 insert into public.organization_members(organization_id,user_id,member_role,invited_by,joined_at)
 values(v_org.id,p_owner_id,'owner',auth.uid(),pg_catalog.now());
 perform public.audit_admin_action('organization_created','organization',v_org.id,jsonb_build_object('type',p_type));
 return v_org;
end $$;
revoke all on function public.create_organization(text,text,uuid) from public,anon,authenticated;
grant execute on function public.create_organization(text,text,uuid) to authenticated;

create or replace function public.request_account_deletion()
returns public.account_deletion_requests language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_row public.account_deletion_requests%rowtype;
begin
 if v_user is null then raise exception using errcode='42501',message='Login required.'; end if;
 insert into public.account_deletion_requests(user_id) values(v_user) returning * into v_row;
 return v_row;
end $$;
revoke all on function public.request_account_deletion() from public,anon,authenticated;
grant execute on function public.request_account_deletion() to authenticated;

create or replace function public.review_account_deletion_request(p_request_id uuid,p_approve boolean,p_note text default null)
returns public.account_deletion_requests language plpgsql security definer set search_path=''
as $$
declare v_row public.account_deletion_requests%rowtype; v_next public.account_deletion_status;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 select * into v_row from public.account_deletion_requests where id=p_request_id for update;
 if not found or v_row.status<>'requested' then raise exception using errcode='P0002',message='Pending deletion request not found.'; end if;
 v_next:=case when p_approve then 'processing'::public.account_deletion_status else 'rejected'::public.account_deletion_status end;
 update public.account_deletion_requests set status=v_next,processed_at=case when p_approve then null else pg_catalog.now() end where id=p_request_id returning * into v_row;
 if p_approve then
  insert into public.account_deletion_jobs(request_id,user_id,operation) values(v_row.id,v_row.user_id,'disable_auth_user');
  insert into public.storage_deletion_jobs(bucket_id,object_path,delete_after)
   select 'identity-documents',d.storage_path,pg_catalog.now()+interval '12 months' from public.verification_documents d where d.user_id=v_row.user_id
   union select 'vehicle-documents',d.storage_path,pg_catalog.now()+interval '12 months' from public.vehicle_documents d where d.user_id=v_row.user_id
   union select 'avatars',p.avatar_path,pg_catalog.now() from public.profiles p where p.id=v_row.user_id and p.avatar_path is not null
  on conflict(bucket_id,object_path) do nothing;
 end if;
 perform public.audit_admin_action(case when p_approve then 'account_deletion_queued' else 'account_deletion_rejected' end,'account_deletion_request',p_request_id,jsonb_build_object('note',nullif(pg_catalog.btrim(p_note),'')));
 return v_row;
end $$;
revoke all on function public.review_account_deletion_request(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.review_account_deletion_request(uuid,boolean,text) to authenticated;

create or replace function public.transition_account_deletion_job(p_job_id uuid,p_status text,p_error text default null)
returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='Service role required.'; end if;
 if p_status not in ('processing','completed','failed') then raise exception using errcode='22023',message='Invalid job status.'; end if;
 update public.account_deletion_jobs set status=p_status,attempts=attempts+case when p_status='failed' then 1 else 0 end,
  available_at=case when p_status='failed' then pg_catalog.now()+interval '15 minutes' else available_at end,last_error=p_error
 where id=p_job_id;
 return found;
end $$;
revoke all on function public.transition_account_deletion_job(uuid,text,text) from public,anon,authenticated;
grant execute on function public.transition_account_deletion_job(uuid,text,text) to service_role;

create or replace function public.record_cash_received(p_booking_id uuid)
returns public.simulated_payments language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_payment public.simulated_payments%rowtype;
begin
 if v_user is null or not public.has_role('driver'::public.app_role) then raise exception using errcode='42501',message='Trip driver login is required.'; end if;
 select p.* into v_payment from public.simulated_payments p join public.bookings b on b.id=p.booking_id
 join public.trips t on t.id=b.trip_id where b.id=p_booking_id and t.driver_id=v_user and b.status in ('confirmed','completed') for update of p;
 if not found or v_payment.status<>'cash_due' then raise exception using errcode='22023',message='No cash due is available for this booking.'; end if;
 update public.simulated_payments set status='cash_received',cash_reported_by=v_user,cash_reported_at=pg_catalog.now()
 where id=v_payment.id returning * into v_payment;
 return v_payment;
end $$;
revoke all on function public.record_cash_received(uuid) from public,anon,authenticated;
grant execute on function public.record_cash_received(uuid) to authenticated;

create or replace function public.request_simulated_refund(p_booking_id uuid,p_reason text)
returns public.refund_requests language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_payment public.simulated_payments%rowtype; v_request public.refund_requests%rowtype;
begin
 if v_user is null or p_reason is null or length(pg_catalog.btrim(p_reason)) not between 5 and 2000 then raise exception using errcode='22023',message='Sign in and provide a refund reason.'; end if;
 select p.* into v_payment from public.simulated_payments p join public.bookings b on b.id=p.booking_id
 where b.id=p_booking_id and b.passenger_id=v_user and b.status='cancelled' for update of p;
 if not found or v_payment.status<>'cash_received' then raise exception using errcode='22023',message='Only cash already marked received on a cancelled booking can be reviewed.'; end if;
 insert into public.refund_requests(simulated_payment_id,requester_id,amount_minor,reason)
 values(v_payment.id,v_user,v_payment.amount_minor,pg_catalog.btrim(p_reason)) returning * into v_request;
 update public.simulated_payments set status='refund_requested' where id=v_payment.id;
 return v_request;
end $$;
revoke all on function public.request_simulated_refund(uuid,text) from public,anon,authenticated;
grant execute on function public.request_simulated_refund(uuid,text) to authenticated;

create or replace function public.review_simulated_refund(p_refund_request_id uuid,p_approve boolean,p_note text default null)
returns public.refund_requests language plpgsql security definer set search_path=''
as $$
declare v_row public.refund_requests%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 select * into v_row from public.refund_requests where id=p_refund_request_id for update;
 if not found or v_row.status<>'open' then raise exception using errcode='P0002',message='Open refund request not found.'; end if;
 update public.refund_requests set status=case when p_approve then 'approved'::public.refund_request_status else 'rejected'::public.refund_request_status end,
  decided_by=auth.uid(),decided_at=pg_catalog.now(),decision_note=nullif(pg_catalog.btrim(p_note),'')
 where id=p_refund_request_id returning * into v_row;
 if not p_approve then
  update public.simulated_payments set status='cash_received' where id=v_row.simulated_payment_id and status='refund_requested';
 end if;
 perform public.audit_admin_action(case when p_approve then 'refund_approved' else 'refund_rejected' end,'refund_request',p_refund_request_id,'{}'::jsonb);
 return v_row;
end $$;
revoke all on function public.review_simulated_refund(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.review_simulated_refund(uuid,boolean,text) to authenticated;

create or replace function public.mark_refund_simulated(p_refund_request_id uuid,p_note text default null)
returns public.refund_requests language plpgsql security definer set search_path=''
as $$
declare v_row public.refund_requests%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 select * into v_row from public.refund_requests where id=p_refund_request_id for update;
 if not found or v_row.status<>'approved' then raise exception using errcode='22023',message='An approved refund request is required.'; end if;
 update public.refund_requests set status='simulated',decision_note=coalesce(nullif(pg_catalog.btrim(p_note),''),decision_note)
  where id=p_refund_request_id returning * into v_row;
 update public.simulated_payments set status='refund_simulated' where id=v_row.simulated_payment_id and status='refund_requested';
 perform public.audit_admin_action('refund_marked_simulated','refund_request',p_refund_request_id,'{}'::jsonb);
 return v_row;
end $$;
revoke all on function public.mark_refund_simulated(uuid,text) from public,anon,authenticated;
grant execute on function public.mark_refund_simulated(uuid,text) to authenticated;

commit;

-- Recorded production migration 20261031204809: phase7b_final_hardening
-- Final hardening: cover remaining foreign keys, explicit deny policies for private worker tables,
-- and a typed organization state.
begin;
do $$ begin create type public.organization_status as enum ('active','suspended','closed'); exception when duplicate_object then null; end $$;
alter table public.organizations drop constraint if exists organizations_status_check;
alter table public.organizations alter column status drop default;
alter table public.organizations alter column status type public.organization_status using status::public.organization_status;
alter table public.organizations alter column status set default 'active'::public.organization_status;

alter table public.support_tickets add column if not exists resolved_at timestamptz;
create index if not exists support_tickets_resolved_at_idx on public.support_tickets(resolved_at) where resolved_at is not null;
create or replace function public.resolve_support_ticket(p_ticket_id uuid,p_note text default null)
returns public.support_tickets language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_row public.support_tickets%rowtype;
begin
 if v_user is null or not (public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role)) then raise exception using errcode='42501',message='Support staff role required.'; end if;
 update public.support_tickets set status='resolved',assigned_to=coalesce(assigned_to,v_user),resolved_at=pg_catalog.now(),closed_at=null
 where id=p_ticket_id and status in ('open','in_progress') returning * into v_row;
 if not found then raise exception using errcode='P0002',message='Open support ticket not found.'; end if;
 if public.has_role('admin'::public.app_role) then perform public.audit_admin_action('support_ticket_resolved','support_ticket',p_ticket_id,jsonb_build_object('note',nullif(pg_catalog.btrim(p_note),''))); end if;
 return v_row;
end $$;
revoke all on function public.resolve_support_ticket(uuid,text) from public,anon,authenticated;
grant execute on function public.resolve_support_ticket(uuid,text) to authenticated;

create index if not exists boarding_events_recorded_by_idx on public.boarding_events(recorded_by);
create index if not exists conversations_driver_id_idx on public.conversations(driver_id);
create index if not exists conversations_rider_id_idx on public.conversations(rider_id);
create index if not exists conversations_trip_id_idx on public.conversations(trip_id);
create index if not exists emergency_incidents_booking_idx on public.emergency_incidents(booking_id);
create index if not exists organizations_created_by_idx on public.organizations(created_by);
create index if not exists ratings_reviewer_idx on public.ratings(reviewer_id);
create index if not exists refund_requests_decided_by_idx on public.refund_requests(decided_by);
create index if not exists report_evidence_uploaded_by_idx on public.report_evidence(uploaded_by);
create index if not exists reports_booking_idx on public.reports(booking_id);
create index if not exists reports_resolved_by_idx on public.reports(resolved_by);
create index if not exists simulated_payments_cash_reported_by_idx on public.simulated_payments(cash_reported_by);
create index if not exists trip_shares_booking_idx on public.trip_shares(booking_id);

create policy account_deletion_jobs_deny_clients on public.account_deletion_jobs for all to authenticated using(false) with check(false);
create policy storage_deletion_jobs_deny_clients on public.storage_deletion_jobs for all to authenticated using(false) with check(false);
create policy notification_outbox_deny_clients on public.notification_outbox for all to authenticated using(false) with check(false);
create policy trip_location_updates_deny_clients on public.trip_location_updates for all to authenticated using(false) with check(false);
create policy trip_shares_deny_clients on public.trip_shares for all to authenticated using(false) with check(false);
commit;

-- Recorded production migration 20261031214058: phase3_trip_stops_and_fares
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

-- Recorded production migration 20261031214345: phase3_availability_rpc_scope
-- Phase 3 security follow-up: expose seat availability only for a published trip or its owner.
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
  where s.trip_id=p_trip_id
    and s.segment_order between p_pickup_order and p_dropoff_order
    and auth.uid() is not null
    and (t.status='published' or t.driver_id=auth.uid())
$$;
revoke all on function public.available_seats(uuid,integer,integer) from public,anon;
grant execute on function public.available_seats(uuid,integer,integer) to authenticated;

-- Recorded production migration 20261031215127: phase4_booking_status_vocabulary
-- Phase 4 booking status vocabulary; keep this migration separate because new enum labels
-- must be committed before later migrations can use them in SQL expressions.
alter type public.booking_status add value if not exists 'expired';
alter type public.booking_status add value if not exists 'refunded';

-- Recorded production migration 20261031215221: phase4_booking_workflows_history
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

-- Recorded production migration 20261031215645: phase5_pricing_snapshots
-- Phase 5, steps 12-14 follow-up: preserve the exact fare used by each booking.
-- Existing per-trip fares remain flexible; this does not introduce a platform fee.

alter table public.bookings
  add column if not exists pricing_snapshot jsonb,
  add column if not exists price_captured_at timestamptz;

-- Older bookings cannot always be reconstructed against the original fare rows;
-- label their stored amount honestly instead of claiming a verified breakdown.
update public.bookings
set pricing_snapshot = pg_catalog.jsonb_build_object(
      'schema_version', 1,
      'currency', 'EGP',
      'fare_source', 'historical_unverified',
      'unit_fare_minor', case when seats_booked > 0 then total_price_minor / seats_booked else null end,
      'seats', seats_booked,
      'total_price_minor', total_price_minor,
      'components', '[]'::jsonb
    ),
    price_captured_at = coalesce(price_captured_at, created_at, pg_catalog.now())
where pricing_snapshot is null;

alter table public.bookings
  alter column pricing_snapshot set not null,
  alter column price_captured_at set not null;

alter table public.bookings
  add constraint bookings_pricing_snapshot_object
    check (pg_catalog.jsonb_typeof(pricing_snapshot) = 'object');

create or replace function public.capture_booking_price_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_override public.trip_fares%rowtype;
  v_unit_fare_minor bigint;
  v_components jsonb;
  v_source text;
begin
  if tg_op = 'UPDATE' then
    if new.pricing_snapshot is distinct from old.pricing_snapshot
       or new.price_captured_at is distinct from old.price_captured_at then
      raise exception using errcode = '22023', message = 'A booking price snapshot is immutable.';
    end if;
    return new;
  end if;

  if new.seats_booked is null or new.seats_booked < 1
     or new.total_price_minor is null or new.total_price_minor < 0 then
    raise exception using errcode = '22023', message = 'A valid booking price and seat count are required.';
  end if;

  select f.* into v_override
  from public.trip_fares f
  where f.trip_id = new.trip_id
    and f.fare_type = 'override'
    and f.from_stop_id = new.pickup_stop_id
    and f.to_stop_id = new.dropoff_stop_id;

  if found then
    v_unit_fare_minor := v_override.price_minor;
    v_source := 'route_override';
    v_components := pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'fare_id', v_override.id,
      'from_stop_id', v_override.from_stop_id,
      'to_stop_id', v_override.to_stop_id,
      'price_minor', v_override.price_minor
    ));
  else
    select coalesce(pg_catalog.sum(f.price_minor), 0)::bigint,
           coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'fare_id', f.id,
             'segment_id', s.id,
             'from_stop_id', s.from_stop_id,
             'to_stop_id', s.to_stop_id,
             'price_minor', f.price_minor
           ) order by s.segment_order), '[]'::jsonb)
      into v_unit_fare_minor, v_components
    from public.trip_segments s
    join public.trip_fares f on f.trip_segment_id = s.id and f.fare_type = 'segment'
    where s.trip_id = new.trip_id
      and s.segment_order between new.pickup_order and new.dropoff_order;
    v_source := 'segment_sum';
  end if;

  if v_unit_fare_minor <= 0
     or new.total_price_minor <> v_unit_fare_minor * new.seats_booked then
    raise exception using errcode = '22023', message = 'Booking total does not match the configured route fare.';
  end if;

  new.pricing_snapshot := pg_catalog.jsonb_build_object(
    'schema_version', 1,
    'currency', 'EGP',
    'fare_source', v_source,
    'unit_fare_minor', v_unit_fare_minor,
    'seats', new.seats_booked,
    'total_price_minor', new.total_price_minor,
    'components', v_components
  );
  new.price_captured_at := pg_catalog.now();
  return new;
end;
$$;

revoke all on function public.capture_booking_price_snapshot() from public, anon, authenticated;

drop trigger if exists bookings_capture_price_snapshot on public.bookings;
create trigger bookings_capture_price_snapshot
before insert or update of pricing_snapshot, price_captured_at on public.bookings
for each row execute function public.capture_booking_price_snapshot();

-- Recorded production migration 20261031215934: phase6_messaging_notifications_ratings_hardening
-- Phase 6, steps 15-17 follow-up: apply chat retention to reads/Realtime,
-- honor push preferences, and keep rating aggregates correct when moderated.

alter table public.notification_preferences
  add column if not exists message_updates boolean not null default true;
grant update (message_updates) on public.notification_preferences to authenticated;

alter table public.notifications drop constraint if exists notifications_category_check;
alter table public.notifications add constraint notifications_category_check
  check (category in ('booking', 'trip', 'message', 'safety', 'support', 'account', 'marketing'));

-- Reads and Realtime visibility must follow the same booking/trip window as send_message.
drop policy if exists messages_participant_read on public.messages;
create policy messages_participant_read on public.messages
for select to authenticated
using (
  exists (
    select 1
    from public.conversations c
    join public.bookings b on b.id = c.booking_id
    join public.trips t on t.id = c.trip_id
    where c.id = messages.conversation_id
      and c.booking_id = messages.booking_id
      and (c.rider_id = (select auth.uid()) or c.driver_id = (select auth.uid()))
      and b.status in ('confirmed', 'completed')
      and t.status <> 'cancelled'
      and (
        t.status <> 'completed'
        or t.arrival_time is null
        or pg_catalog.now() <= t.arrival_time + pg_catalog.make_interval(days => coalesce(
          (select (s.value #>> '{}')::integer from public.app_settings s where s.key = 'chat_retention_days_after_trip'),
          30
        ))
      )
  )
);

-- Always store the in-app notification. Queue a push only when both the global
-- push switch and the matching category preference are enabled.
create or replace function public.enqueue_notification(
  p_recipient uuid,
  p_category text,
  p_event text,
  p_title jsonb,
  p_body jsonb,
  p_data jsonb,
  p_key text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_push_enabled boolean;
  v_category_enabled boolean;
begin
  if p_recipient is null or (p_recipient = auth.uid() and p_event = 'new_message') then
    return;
  end if;

  insert into public.notifications(recipient_id, category, title, body, data, idempotency_key)
  values (p_recipient, p_category, p_title, p_body, coalesce(p_data, '{}'::jsonb), p_key)
  on conflict (idempotency_key) do nothing;

  select coalesce(np.push_enabled, true),
         case p_category
           when 'booking' then coalesce(np.booking_updates, true)
           when 'trip' then coalesce(np.trip_updates, true)
           when 'message' then coalesce(np.message_updates, true)
           when 'safety' then coalesce(np.safety_alerts, true)
           when 'support' then coalesce(np.support_updates, true)
           when 'marketing' then coalesce(np.marketing_messages, true)
           when 'account' then true
           else false
         end
    into v_push_enabled, v_category_enabled
  from (select 1) seed
  left join public.notification_preferences np on np.user_id = p_recipient;

  if v_push_enabled and v_category_enabled then
    insert into public.notification_outbox(recipient_id, category, event_type, payload, idempotency_key)
    values (p_recipient, p_category, p_event, coalesce(p_data, '{}'::jsonb), p_key)
    on conflict (idempotency_key) do nothing;
  end if;
end;
$$;
revoke all on function public.enqueue_notification(uuid, text, text, jsonb, jsonb, jsonb, text) from public, anon, authenticated;

-- Keep profile rating averages/counts correct for inserts, moderation changes,
-- reassignment, or deletion of a rating.
create or replace function public.refresh_profile_rating_after_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' or (tg_op = 'UPDATE' and old.reviewee_id is distinct from new.reviewee_id) then
    update public.profiles p
    set rating_count = (select count(*)::integer from public.ratings r where r.reviewee_id = old.reviewee_id and r.is_visible),
        rating_avg = coalesce((select round(avg(r.score)::numeric, 2) from public.ratings r where r.reviewee_id = old.reviewee_id and r.is_visible), 0)
    where p.id = old.reviewee_id;
  end if;

  if tg_op <> 'DELETE' then
    update public.profiles p
    set rating_count = (select count(*)::integer from public.ratings r where r.reviewee_id = new.reviewee_id and r.is_visible),
        rating_avg = coalesce((select round(avg(r.score)::numeric, 2) from public.ratings r where r.reviewee_id = new.reviewee_id and r.is_visible), 0)
    where p.id = new.reviewee_id;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.refresh_profile_rating_after_change() from public, anon, authenticated;
drop trigger if exists rating_profile_summary on public.ratings;
create trigger rating_profile_summary
after insert or update of is_visible, score, reviewee_id or delete on public.ratings
for each row execute function public.refresh_profile_rating_after_change();

-- The notification inbox is user-owned under RLS; enable it for live inbox updates.
do $$
begin
  if exists (select 1 from pg_catalog.pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_catalog.pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
     ) then
    execute 'alter publication supabase_realtime add table public.notifications';
  end if;
end;
$$;

-- Recorded production migration 20261031220302: phase7_reports_support_retention_hardening
-- Phase 7, steps 18-20 follow-up: route support writes through the RPC,
-- keep ticket state transitions consistent, and prevent assigning closed reports.

-- A ticket must be created with its first public message by create_support_ticket().
revoke insert on public.support_tickets from authenticated;

create or replace function public.assign_report_reviewer(p_report_id uuid, p_reviewer_id uuid)
returns public.report_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.report_assignments%rowtype;
  v_status public.report_status;
begin
  if not public.has_role('admin'::public.app_role) then
    raise exception using errcode = '42501', message = 'Administrator role required.';
  end if;
  if not exists (
    select 1 from public.user_roles
    where user_id = p_reviewer_id and role = 'reviewer'::public.app_role
  ) then
    raise exception using errcode = '22023', message = 'Selected account is not a reviewer.';
  end if;

  select status into v_status
  from public.reports
  where id = p_report_id
  for update;
  if not found or v_status not in ('open', 'under_review') then
    raise exception using errcode = '22023', message = 'Only an open or under-review report can be assigned.';
  end if;

  insert into public.report_assignments(report_id, reviewer_id, assigned_by)
  values (p_report_id, p_reviewer_id, auth.uid())
  on conflict (report_id, reviewer_id)
  do update set assigned_by = excluded.assigned_by, assigned_at = pg_catalog.now()
  returning * into v_row;

  update public.reports set status = 'under_review'
  where id = p_report_id and status = 'open';

  perform public.audit_admin_action(
    'report_reviewer_assigned', 'report', p_report_id,
    pg_catalog.jsonb_build_object('reviewer_id', p_reviewer_id)
  );
  return v_row;
end;
$$;
revoke all on function public.assign_report_reviewer(uuid, uuid) from public, anon, authenticated;
grant execute on function public.assign_report_reviewer(uuid, uuid) to authenticated;

create or replace function public.add_support_message(p_ticket_id uuid, p_body text, p_is_internal boolean default false)
returns public.support_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ticket public.support_tickets%rowtype;
  v_message public.support_messages%rowtype;
  v_staff boolean;
begin
  if v_user is null or p_body is null or length(pg_catalog.btrim(p_body)) not between 1 and 5000 then
    raise exception using errcode = '22023', message = 'Sign in and provide a valid message.';
  end if;
  v_staff := public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role);

  select * into v_ticket from public.support_tickets where id = p_ticket_id for update;
  if not found or (v_ticket.user_id <> v_user and not v_staff) then
    raise exception using errcode = '42501', message = 'Ticket not found or not accessible.';
  end if;
  if p_is_internal and not v_staff then
    raise exception using errcode = '42501', message = 'Only support staff can create internal notes.';
  end if;
  if v_ticket.status = 'closed' then
    raise exception using errcode = '22023', message = 'This ticket is closed.';
  end if;
  if v_ticket.status = 'resolved' and not v_staff then
    raise exception using errcode = '22023', message = 'This ticket is resolved.';
  end if;

  insert into public.support_messages(ticket_id, sender_id, body, is_internal)
  values (p_ticket_id, v_user, pg_catalog.btrim(p_body), p_is_internal)
  returning * into v_message;

  if v_staff and v_ticket.status in ('open', 'resolved') then
    update public.support_tickets
    set status = 'in_progress',
        assigned_to = coalesce(assigned_to, v_user),
        resolved_at = null,
        closed_at = null
    where id = p_ticket_id;
  end if;
  return v_message;
end;
$$;
revoke all on function public.add_support_message(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.add_support_message(uuid, text, boolean) to authenticated;

create or replace function public.close_own_support_ticket(p_ticket_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.support_tickets
  set status = 'closed', closed_at = pg_catalog.now()
  where id = p_ticket_id
    and user_id = auth.uid()
    and status in ('open', 'in_progress', 'resolved');
  return found;
end;
$$;
revoke all on function public.close_own_support_ticket(uuid) from public, anon, authenticated;
grant execute on function public.close_own_support_ticket(uuid) to authenticated;

-- Recorded production migration 20261031220526: phase9_configurable_document_retention
-- Phase 9, step 22: apply the admin-managed document retention setting when
-- an account deletion is approved. Existing queued dates remain unchanged.

create or replace function public.review_account_deletion_request(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null
)
returns public.account_deletion_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.account_deletion_requests%rowtype;
  v_next public.account_deletion_status;
  v_retention_months integer;
begin
  if not public.has_role('admin'::public.app_role) then
    raise exception using errcode = '42501', message = 'Administrator role required.';
  end if;

  select (s.value #>> '{}')::integer
  into v_retention_months
  from public.app_settings s
  where s.key = 'identity_document_retention_months_after_closure';
  v_retention_months := coalesce(v_retention_months, 12);
  if v_retention_months < 1 or v_retention_months > 120 then
    raise exception using errcode = '22023', message = 'Identity document retention must be between 1 and 120 months.';
  end if;

  select * into v_row
  from public.account_deletion_requests
  where id = p_request_id
  for update;
  if not found or v_row.status <> 'requested' then
    raise exception using errcode = 'P0002', message = 'Pending deletion request not found.';
  end if;

  v_next := case when p_approve then 'processing'::public.account_deletion_status
                 else 'rejected'::public.account_deletion_status end;
  update public.account_deletion_requests
  set status = v_next,
      processed_at = case when p_approve then null else pg_catalog.now() end
  where id = p_request_id
  returning * into v_row;

  if p_approve then
    insert into public.account_deletion_jobs(request_id, user_id, operation)
    values (v_row.id, v_row.user_id, 'disable_auth_user');

    insert into public.storage_deletion_jobs(bucket_id, object_path, delete_after)
    select 'identity-documents', d.storage_path,
           pg_catalog.now() + pg_catalog.make_interval(months => v_retention_months)
    from public.verification_documents d
    where d.user_id = v_row.user_id
    union
    select 'vehicle-documents', d.storage_path,
           pg_catalog.now() + pg_catalog.make_interval(months => v_retention_months)
    from public.vehicle_documents d
    where d.user_id = v_row.user_id
    union
    select 'avatars', p.avatar_path, pg_catalog.now()
    from public.profiles p
    where p.id = v_row.user_id and p.avatar_path is not null
    on conflict (bucket_id, object_path) do nothing;
  end if;

  perform public.audit_admin_action(
    case when p_approve then 'account_deletion_queued' else 'account_deletion_rejected' end,
    'account_deletion_request', p_request_id,
    pg_catalog.jsonb_build_object('note', nullif(pg_catalog.btrim(p_note), ''),
                                 'document_retention_months', v_retention_months)
  );
  return v_row;
end;
$$;
revoke all on function public.review_account_deletion_request(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.review_account_deletion_request(uuid, boolean, text) to authenticated;

-- Recorded production migration 20261031220635: phase9_fk_indexes
-- Phase 9: add indexes for foreign keys that are not covered by existing leading index columns.
create index if not exists booking_status_history_changed_by_idx
  on public.booking_status_history (changed_by);

create index if not exists bookings_dropoff_stop_trip_idx
  on public.bookings (dropoff_stop_id, trip_id);

create index if not exists bookings_pickup_stop_trip_idx
  on public.bookings (pickup_stop_id, trip_id);

create index if not exists trip_fares_from_stop_trip_idx
  on public.trip_fares (from_stop_id, trip_id);

create index if not exists trip_fares_to_stop_trip_idx
  on public.trip_fares (to_stop_id, trip_id);

create index if not exists trip_fares_segment_trip_idx
  on public.trip_fares (trip_segment_id, trip_id);

create index if not exists trip_segments_from_stop_trip_idx
  on public.trip_segments (from_stop_id, trip_id);

create index if not exists trip_segments_to_stop_trip_idx
  on public.trip_segments (to_stop_id, trip_id);

create index if not exists trip_stops_approved_stop_city_idx
  on public.trip_stops (approved_stop_id, city_id);
