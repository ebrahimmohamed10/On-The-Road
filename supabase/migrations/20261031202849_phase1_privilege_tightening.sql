-- Phase 1 follow-up: close direct status writes, remove an avoidable
-- SECURITY DEFINER helper, and tighten profile policy evaluation.
begin;

drop index if exists public.user_roles_user_id_idx;
create index if not exists user_roles_assigned_by_idx on public.user_roles(assigned_by);

drop policy if exists profiles_select_own on public.profiles;
drop policy if exists profiles_select_approved_driver_directory on public.profiles;
create policy profiles_select_owner_or_approved_driver
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or (role = 'driver' and verification_status = 'approved')
  );

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

revoke insert on table public.trips from authenticated;
revoke insert (driver_id, origin_city, destination_city, departure_time, arrival_time, total_seats, notes, status)
  on table public.trips from authenticated;
revoke update (status) on table public.trips from authenticated;
revoke update (status) on table public.bookings from authenticated;

commit;
