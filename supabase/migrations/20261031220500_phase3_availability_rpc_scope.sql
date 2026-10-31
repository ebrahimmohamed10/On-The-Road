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
