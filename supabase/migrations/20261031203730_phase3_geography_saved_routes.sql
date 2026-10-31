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
