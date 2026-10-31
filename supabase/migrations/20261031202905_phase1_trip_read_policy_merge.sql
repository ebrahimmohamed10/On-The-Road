-- Phase 1 advisor fix: combine trip discovery and owner visibility to avoid
-- multiple permissive SELECT policies while retaining both access paths.
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
