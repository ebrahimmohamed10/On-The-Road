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

-- Backfill the normalized role source from database-controlled legacy values.
-- Every current user remains a rider; existing approved drivers keep that
-- additional capability. No user metadata is used for authorization.
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

-- Move identity number and birth date from legacy verification submissions to
-- the private table, then scrub them from the legacy row in the same transaction.
alter table public.verification_requests
  alter column national_id drop not null,
  alter column date_of_birth drop not null;

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

-- Ensure every existing and new public table has standard timestamps and a
-- consistent update trigger without replacing any primary keys or user data.
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

-- The auth trigger creates all baseline rows. Display name metadata is user
-- input; role metadata is deliberately ignored.
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

-- Restrict the base profile table to safe columns; RLS allows only the owner
-- and approved driver rows. The legacy client-facing driver view is retained
-- but now honors invoker permissions and underlying RLS.
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

-- Phase 1 tables are private by default. No client can assign roles or change
-- deletion-request status; those operations will use audited RPCs in later phases.
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

-- PII remains accessible only through owner-scoped private details or assigned
-- review APIs. The legacy profile columns are retained temporarily for
-- migration compatibility, but are no longer exposed or writable by clients.
revoke select (phone, national_id, id_front_url, id_back_url, selfie_url, license_url, car_plate)
  on public.profiles from authenticated;
revoke update (phone, role, verification_status, national_id, id_front_url, id_back_url, selfie_url, license_url, car_model, car_color, car_plate, rating, trips_count)
  on public.profiles from authenticated;

-- Make legacy verification insert store identity data only in user_private_details.
revoke select (national_id, date_of_birth, id_front_path, id_back_path, selfie_path, license_front_path, license_back_path, reviewer_notes)
  on public.verification_requests from authenticated;

commit;
