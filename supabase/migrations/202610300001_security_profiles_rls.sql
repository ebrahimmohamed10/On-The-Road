-- Phase 1, Step 1: least-privilege RLS and profile lifecycle.
-- Apply manually to the project after reviewing. This migration does not run
-- from the app and has not been applied to the live Supabase project.

begin;

-- Fail closed for every current public base/partitioned table, including any
-- table added to this schema after the local baseline was written.
do $$
declare
  table_record record;
begin
  for table_record in
    select n.nspname as schema_name, c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
  loop
    execute format(
      'alter table %I.%I enable row level security',
      table_record.schema_name,
      table_record.table_name
    );
  end loop;
end;
$$;

-- Replace the baseline policies on the five tables defined by
-- supabase_schema.sql with the policy set below.
do $$
declare
  policy_record record;
begin
  for policy_record in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename in ('profiles', 'trips', 'trip_segments', 'bookings', 'messages')
  loop
    execute format(
      'drop policy %I on %I.%I',
      policy_record.policyname,
      policy_record.schemaname,
      policy_record.tablename
    );
  end loop;
end;
$$;

-- Profiles are private by default. Users may access only their own row, and
-- column grants prevent direct changes to role, verification, rating, and
-- Auth-managed phone fields.
revoke all on table public.profiles from public, anon, authenticated;
grant select on table public.profiles to authenticated;
grant insert (id, name, avatar_url) on table public.profiles to authenticated;
grant update (
  name,
  avatar_url,
  national_id,
  id_front_url,
  id_back_url,
  selfie_url,
  license_url,
  car_model,
  car_color,
  car_plate
) on table public.profiles to authenticated;

create policy profiles_select_own
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy profiles_insert_own
  on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);

create policy profiles_update_own
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- A narrow driver directory is the only cross-user profile surface. PostgreSQL
-- views are security-definer by default; this view deliberately uses the
-- migration owner to read through profiles RLS, but projects only public
-- fields and only approved drivers. No private identifiers/documents are
-- included in its result.
create or replace view public.driver_public_profiles
with (security_invoker = false, security_barrier = true)
as
select
  id,
  name,
  avatar_url,
  rating,
  trips_count,
  car_model,
  car_color
from public.profiles
where role = 'driver'
  and verification_status = 'approved';

revoke all on table public.driver_public_profiles from public, anon, authenticated;
grant select on table public.driver_public_profiles to authenticated;

-- New Auth users receive a profile synchronously. User metadata is untrusted:
-- only passenger/driver roles are accepted; admin and verification/rating
-- fields always retain database defaults.
create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role text;
begin
  requested_role := new.raw_user_meta_data ->> 'role';

  insert into public.profiles (id, name, phone, role)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
      nullif(new.phone, ''),
      'New user'
    ),
    new.phone,
    case when requested_role = 'driver' then 'driver' else 'passenger' end
  );

  return new;
end;
$$;

revoke all on function public.handle_new_auth_user_profile() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute function public.handle_new_auth_user_profile();

-- Authenticated users may discover open (upcoming) trips. Trip ownership and
-- the driver's profile role are checked on writes. No segment write path is
-- enabled here because trip publishing is outside this phase.
revoke all on table public.trips from public, anon, authenticated;
grant select on table public.trips to authenticated;
grant insert (
  driver_id,
  origin_city,
  destination_city,
  departure_time,
  arrival_time,
  total_seats,
  notes,
  status
) on table public.trips to authenticated;
grant update (
  origin_city,
  destination_city,
  departure_time,
  arrival_time,
  total_seats,
  notes,
  status
) on table public.trips to authenticated;

create policy trips_read_open_authenticated
  on public.trips for select to authenticated
  using (
    (select auth.uid()) is not null
    and status = 'upcoming'
  );

create policy trips_insert_as_owning_driver
  on public.trips for insert to authenticated
  with check (
    driver_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'driver'
    )
  );

create policy trips_update_as_owning_driver
  on public.trips for update to authenticated
  using (
    driver_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'driver'
    )
  )
  with check (
    driver_id = (select auth.uid())
    and exists (
      select 1 from public.profiles p
      where p.id = (select auth.uid())
        and p.role = 'driver'
    )
  );

revoke all on table public.trip_segments from public, anon, authenticated;
grant select on table public.trip_segments to authenticated;
create policy trip_segments_read_authenticated
  on public.trip_segments for select to authenticated
  using (
    (select auth.uid()) is not null
    and exists (
      select 1 from public.trips t
      where t.id = trip_segments.trip_id
        and t.status = 'upcoming'
    )
  );

-- RLS on trips intentionally hides non-open trips from passengers. This
-- narrow helper lets the booking policy still recognize a driver as owner of
-- their own trip regardless of its current status without exposing trip rows.
create or replace function public.is_own_trip(p_trip_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.trips t
    where t.id = p_trip_id
      and t.driver_id = (select auth.uid())
  );
$$;

revoke all on function public.is_own_trip(uuid) from public, anon, authenticated;
grant execute on function public.is_own_trip(uuid) to authenticated;

-- Bookings are visible to their passenger and the trip's driver. Client
-- inserts are removed; the later create_booking RPC is the only insert path.
-- The only client update permitted is cancellation from pending/confirmed.
revoke all on table public.bookings from public, anon, authenticated;
grant select on table public.bookings to authenticated;
grant update (status) on table public.bookings to authenticated;

create policy bookings_select_passenger_or_trip_driver
  on public.bookings for select to authenticated
  using (
    passenger_id = (select auth.uid())
    or public.is_own_trip(trip_id)
  );

create policy bookings_cancel_own
  on public.bookings for update to authenticated
  using (
    passenger_id = (select auth.uid())
    and status in ('pending', 'confirmed')
  )
  with check (
    passenger_id = (select auth.uid())
    and status = 'cancelled'
  );

revoke all on table public.messages from public, anon, authenticated;
-- RLS remains enabled with no client policies until a separately reviewed chat
-- authorization model is implemented.

-- The legacy helper exposes aggregate seat data; keep it authenticated-only.
revoke all on function public.available_seats(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.available_seats(uuid, integer, integer) to authenticated;

commit;
