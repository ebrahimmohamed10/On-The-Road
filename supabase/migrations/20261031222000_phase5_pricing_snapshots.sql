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

