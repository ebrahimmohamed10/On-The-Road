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
