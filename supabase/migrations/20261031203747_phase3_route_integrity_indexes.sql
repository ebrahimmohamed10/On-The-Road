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
