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
