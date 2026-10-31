-- Phase 2: verification, reviewer assignments, driver capability, and vehicles.
begin;

-- The client insert contract remains available while status becomes an enum.
drop policy if exists "Users read own verification request" on public.verification_requests;
drop policy if exists "Users submit own verification request" on public.verification_requests;

do $$ begin
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='verification_status') then
    create type public.verification_status as enum ('draft','submitted','in_review','needs_resubmission','approved','rejected');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='verification_document_type') then
    create type public.verification_document_type as enum ('national_id_front','national_id_back','face_scan','driver_license_front','driver_license_back','vehicle_license_front','vehicle_license_back');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='document_review_status') then
    create type public.document_review_status as enum ('submitted','accepted','rejected','needs_resubmission');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='driver_profile_status') then
    create type public.driver_profile_status as enum ('draft','submitted','in_review','needs_resubmission','approved','rejected','suspended');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='vehicle_status') then
    create type public.vehicle_status as enum ('draft','submitted','in_review','needs_resubmission','approved','rejected','suspended');
  end if;
  if not exists (select 1 from pg_type t join pg_namespace n on n.oid=t.typnamespace where n.nspname='public' and t.typname='verification_decision') then
    create type public.verification_decision as enum ('approved','rejected','needs_resubmission');
  end if;
end $$;

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create table public.allowed_status_transitions (
  id uuid primary key default extensions.gen_random_uuid(),
  entity_type text not null check(entity_type in ('verification','driver_profile','vehicle','trip','booking','deletion')),
  from_status text not null,
  to_status text not null,
  actor_role public.app_role,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique(entity_type,from_status,to_status,actor_role),
  check(from_status<>to_status)
);
create table public.audit_log (
  id uuid primary key default extensions.gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null check(length(btrim(action))>0),
  entity_type text not null,
  entity_id uuid,
  occurred_at timestamptz not null default pg_catalog.now(),
  metadata jsonb not null default '{}'::jsonb check(jsonb_typeof(metadata)='object'),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);
create table public.driver_profiles (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  verification_request_id uuid references public.verification_requests(id) on delete set null,
  status public.driver_profile_status not null default 'draft',
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check((status='approved')=(approved_at is not null))
);
create table public.vehicles (
  id uuid primary key default extensions.gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  make text not null check(length(btrim(make)) between 1 and 60),
  model text not null check(length(btrim(model)) between 1 and 80),
  color text not null check(length(btrim(color)) between 1 and 40),
  plate text not null check(length(btrim(plate)) between 3 and 24),
  manufacture_year smallint check(manufacture_year between 1980 and extract(year from pg_catalog.now())::integer+1),
  seats smallint not null check(seats between 1 and 8),
  status public.vehicle_status not null default 'draft',
  approved_at timestamptz,
  approved_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check((status='approved')=(approved_at is not null and approved_by is not null))
);
create table public.reviewer_assignments (
  id uuid primary key default extensions.gen_random_uuid(),
  reviewer_id uuid not null references public.profiles(id) on delete cascade,
  verification_request_id uuid references public.verification_requests(id) on delete cascade,
  vehicle_id uuid references public.vehicles(id) on delete cascade,
  assigned_by uuid references public.profiles(id) on delete set null,
  assigned_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check(num_nonnulls(verification_request_id,vehicle_id)=1),
  unique(reviewer_id,verification_request_id),
  unique(reviewer_id,vehicle_id)
);
create table public.verification_documents (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  verification_request_id uuid not null references public.verification_requests(id) on delete cascade,
  document_type public.verification_document_type not null,
  storage_path text not null unique,
  version integer not null default 1 check(version>0),
  status public.document_review_status not null default 'submitted',
  uploaded_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique(verification_request_id,document_type,version)
);
create table public.vehicle_documents (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete cascade,
  document_type public.verification_document_type not null check(document_type in ('vehicle_license_front','vehicle_license_back')),
  storage_path text not null unique,
  version integer not null default 1 check(version>0),
  status public.document_review_status not null default 'submitted',
  uploaded_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  unique(vehicle_id,document_type,version)
);
create table public.verification_checks (
  id uuid primary key default extensions.gen_random_uuid(),
  verification_request_id uuid not null references public.verification_requests(id) on delete cascade,
  check_type text not null check(check_type in ('ocr','document_consistency','face_match','liveness')),
  provider text not null,
  result text not null check(result in ('pending','passed','failed','needs_human_review','error')),
  score numeric(5,4) check(score between 0 and 1),
  extracted_fields jsonb not null default '{}'::jsonb check(jsonb_typeof(extracted_fields)='object'),
  is_preliminary boolean not null default true check(is_preliminary),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now()
);
create table public.verification_reviews (
  id uuid primary key default extensions.gen_random_uuid(),
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  verification_request_id uuid references public.verification_requests(id) on delete cascade,
  vehicle_id uuid references public.vehicles(id) on delete cascade,
  decision public.verification_decision not null,
  reviewer_notes text,
  decided_at timestamptz not null default pg_catalog.now(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check(num_nonnulls(verification_request_id,vehicle_id)=1)
);

-- Convert old text states without deleting rows. 'pending' represented a new
-- request; 'resubmission_required' maps to the explicit new enum value.
alter table public.verification_requests drop constraint if exists verification_requests_status_check;
alter table public.verification_requests alter column status drop default;
alter table public.verification_requests alter column status type public.verification_status using
  (case status when 'pending' then 'submitted' when 'resubmission_required' then 'needs_resubmission' else status end)::public.verification_status;
alter table public.verification_requests alter column status set default 'submitted'::public.verification_status;

insert into public.allowed_status_transitions(entity_type,from_status,to_status) values
 ('verification','draft','submitted'),('verification','submitted','in_review'),('verification','submitted','approved'),('verification','submitted','rejected'),('verification','submitted','needs_resubmission'),
 ('verification','in_review','approved'),('verification','in_review','rejected'),('verification','in_review','needs_resubmission'),('verification','needs_resubmission','submitted'),
 ('driver_profile','draft','submitted'),('driver_profile','submitted','in_review'),('driver_profile','submitted','approved'),('driver_profile','submitted','rejected'),('driver_profile','in_review','approved'),('driver_profile','in_review','rejected'),('driver_profile','in_review','needs_resubmission'),('driver_profile','needs_resubmission','submitted'),
 ('vehicle','draft','submitted'),('vehicle','submitted','in_review'),('vehicle','submitted','approved'),('vehicle','submitted','rejected'),('vehicle','in_review','approved'),('vehicle','in_review','rejected'),('vehicle','in_review','needs_resubmission'),('vehicle','needs_resubmission','submitted')
on conflict do nothing;

-- Migrate the existing approved-driver designation. Vehicle approval remains
-- separate; no vehicle is inferred from the old profile fields.
insert into public.driver_profiles(user_id,status,approved_at)
select id,'approved'::public.driver_profile_status,created_at
from public.profiles where role='driver' and verification_status='approved'
on conflict(user_id) do nothing;

create index on public.allowed_status_transitions(entity_type,from_status);
create index on public.audit_log(entity_type,entity_id,occurred_at desc);
create index on public.driver_profiles(status);
create index on public.vehicles(owner_id,created_at desc);
create index on public.vehicles(status);
create index on public.reviewer_assignments(reviewer_id,assigned_at desc);
create index on public.reviewer_assignments(verification_request_id);
create index on public.reviewer_assignments(vehicle_id);
create index on public.verification_documents(verification_request_id);
create index on public.verification_documents(user_id);
create index on public.vehicle_documents(vehicle_id);
create index on public.vehicle_documents(user_id);
create index on public.verification_checks(verification_request_id,created_at desc);
create index on public.verification_reviews(verification_request_id,decided_at desc);
create index on public.verification_reviews(vehicle_id,decided_at desc);

do $$ declare t text; begin
  foreach t in array array['allowed_status_transitions','audit_log','driver_profiles','vehicles','reviewer_assignments','verification_documents','vehicle_documents','verification_checks','verification_reviews'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
  end loop;
end $$;

create or replace function public.is_reviewer_for_verification(p_request_id uuid)
returns boolean language sql stable security invoker set search_path=''
as $$ select auth.uid() is not null and public.has_role('reviewer'::public.app_role) and exists(select 1 from public.reviewer_assignments ra where ra.reviewer_id=auth.uid() and ra.verification_request_id=p_request_id); $$;
revoke all on function public.is_reviewer_for_verification(uuid) from public,anon,authenticated;
grant execute on function public.is_reviewer_for_verification(uuid) to authenticated;
create or replace function public.is_reviewer_for_vehicle(p_vehicle_id uuid)
returns boolean language sql stable security invoker set search_path=''
as $$ select auth.uid() is not null and public.has_role('reviewer'::public.app_role) and exists(select 1 from public.reviewer_assignments ra where ra.reviewer_id=auth.uid() and ra.vehicle_id=p_vehicle_id); $$;
revoke all on function public.is_reviewer_for_vehicle(uuid) from public,anon,authenticated;
grant execute on function public.is_reviewer_for_vehicle(uuid) to authenticated;
create or replace function public.can_transition(p_entity text,p_from text,p_to text)
returns boolean language sql stable security invoker set search_path=''
as $$ select exists(select 1 from public.allowed_status_transitions x where x.entity_type=p_entity and x.from_status=p_from and x.to_status=p_to); $$;
revoke all on function public.can_transition(text,text,text) from public,anon,authenticated;
grant execute on function public.can_transition(text,text,text) to authenticated;

grant select on public.allowed_status_transitions to authenticated;
create policy allowed_status_transitions_read on public.allowed_status_transitions for select to authenticated using(true);

grant select(id,user_id,user_role,status,submitted_at,created_at,updated_at) on public.verification_requests to authenticated;
create policy verification_requests_owner_or_reviewer_read on public.verification_requests for select to authenticated using(user_id=(select auth.uid()) or public.is_reviewer_for_verification(id) or public.is_admin());
create policy verification_requests_submit_own on public.verification_requests for insert to authenticated with check(user_id=(select auth.uid()) and status='submitted'::public.verification_status and reviewer_notes is null);

grant select(id,user_id,verification_request_id,document_type,storage_path,version,status,uploaded_at,created_at,updated_at) on public.verification_documents to authenticated;
create policy verification_documents_owner_or_reviewer_read on public.verification_documents for select to authenticated using(user_id=(select auth.uid()) or public.is_reviewer_for_verification(verification_request_id) or public.is_admin());
grant select(id,verification_request_id,check_type,provider,result,score,extracted_fields,is_preliminary,created_at) on public.verification_checks to authenticated;
create policy verification_checks_owner_or_reviewer_read on public.verification_checks for select to authenticated using(exists(select 1 from public.verification_requests vr where vr.id=verification_request_id and vr.user_id=(select auth.uid())) or public.is_reviewer_for_verification(verification_request_id) or public.is_admin());
grant insert(verification_request_id,check_type,provider,result,score,extracted_fields,is_preliminary) on public.verification_checks to service_role;
grant update(result,score,extracted_fields) on public.verification_checks to service_role;

grant select on public.driver_profiles to authenticated;
grant insert(user_id,verification_request_id) on public.driver_profiles to authenticated;
create policy driver_profiles_owner_or_approved_read on public.driver_profiles for select to authenticated using(user_id=(select auth.uid()) or status='approved' or public.is_admin());
create policy driver_profiles_owner_submit on public.driver_profiles for insert to authenticated with check(user_id=(select auth.uid()) and status='draft' and approved_at is null and approved_by is null);

grant select(id,owner_id,make,model,color,plate,manufacture_year,seats,status,approved_at,approved_by,created_at,updated_at) on public.vehicles to authenticated;
grant insert(owner_id,make,model,color,plate,manufacture_year,seats) on public.vehicles to authenticated;
grant update(make,model,color,plate,manufacture_year,seats) on public.vehicles to authenticated;
create policy vehicles_owner_or_approved_read on public.vehicles for select to authenticated using(owner_id=(select auth.uid()) or status='approved' or public.is_admin());
create policy vehicles_owner_insert_draft on public.vehicles for insert to authenticated with check(owner_id=(select auth.uid()) and status='draft' and approved_at is null and approved_by is null);
create policy vehicles_owner_update_draft on public.vehicles for update to authenticated using(owner_id=(select auth.uid()) and status in ('draft','needs_resubmission')) with check(owner_id=(select auth.uid()) and status in ('draft','needs_resubmission'));

grant select on public.reviewer_assignments to authenticated;
create policy reviewer_assignments_assigned_or_admin_read on public.reviewer_assignments for select to authenticated using(reviewer_id=(select auth.uid()) or public.is_admin());
grant select on public.vehicle_documents to authenticated;
grant insert(user_id,vehicle_id,document_type,storage_path,version) on public.vehicle_documents to authenticated;
create policy vehicle_documents_owner_or_reviewer_read on public.vehicle_documents for select to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.reviewer_assignments ra where ra.vehicle_id=vehicle_documents.vehicle_id and ra.reviewer_id=(select auth.uid())) or public.is_admin());
create policy vehicle_documents_owner_insert on public.vehicle_documents for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.vehicles v where v.id=vehicle_id and v.owner_id=(select auth.uid()) and v.status in ('draft','needs_resubmission')));
grant select on public.verification_reviews to authenticated;
create policy verification_reviews_reviewer_or_admin_read on public.verification_reviews for select to authenticated using(public.is_admin() or (reviewer_id=(select auth.uid()) and ((verification_request_id is not null and public.is_reviewer_for_verification(verification_request_id)) or (vehicle_id is not null and exists(select 1 from public.reviewer_assignments ra where ra.vehicle_id=verification_reviews.vehicle_id and ra.reviewer_id=(select auth.uid()))))));
grant select on public.audit_log to authenticated;
create policy audit_log_admin_read on public.audit_log for select to authenticated using(public.is_admin());

drop policy if exists profiles_select_owner_or_approved_driver on public.profiles;
create policy profiles_select_owner_or_approved_driver on public.profiles for select to authenticated using(id=(select auth.uid()) or exists(select 1 from public.driver_profiles dp where dp.user_id=profiles.id and dp.status='approved'));
create or replace view public.driver_public_profiles with(security_invoker=true,security_barrier=true) as
select p.id,p.name,p.avatar_url,p.rating,p.trips_count,p.car_model,p.car_color from public.profiles p join public.driver_profiles dp on dp.user_id=p.id where dp.status='approved';
create or replace view public.public_driver_profiles with(security_invoker=true,security_barrier=true) as
select p.id,p.name,p.avatar_url,p.avatar_path,p.rating_avg,p.rating_count,p.trips_count,p.car_model,p.car_color from public.profiles p join public.driver_profiles dp on dp.user_id=p.id where dp.status='approved';
revoke all on public.driver_public_profiles,public.public_driver_profiles from public,anon,authenticated;
grant select on public.driver_public_profiles,public.public_driver_profiles to authenticated;

create or replace function private.capture_verification_documents()
returns trigger language plpgsql security definer set search_path=''
as $$ begin
  if auth.uid() is null or auth.uid() is distinct from new.user_id then raise exception using errcode='42501',message='Cannot submit another user verification request.'; end if;
  insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path) values
    (new.user_id,new.id,'national_id_front',new.id_front_path),(new.user_id,new.id,'national_id_back',new.id_back_path),(new.user_id,new.id,'face_scan',new.selfie_path)
    on conflict(verification_request_id,document_type,version) do nothing;
  if new.license_front_path is not null then insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path) values(new.user_id,new.id,'driver_license_front',new.license_front_path) on conflict(verification_request_id,document_type,version) do nothing; end if;
  if new.license_back_path is not null then insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path) values(new.user_id,new.id,'driver_license_back',new.license_back_path) on conflict(verification_request_id,document_type,version) do nothing; end if;
  update public.verification_requests set id_front_path=null,id_back_path=null,selfie_path=null,license_front_path=null,license_back_path=null where id=new.id;
  if new.user_role='driver' then insert into public.driver_profiles(user_id,verification_request_id,status) values(new.user_id,new.id,'submitted') on conflict(user_id) do update set verification_request_id=excluded.verification_request_id; end if;
  return null;
end $$;
revoke all on function private.capture_verification_documents() from public,anon,authenticated;
create trigger verification_requests_normalize_documents after insert on public.verification_requests for each row execute function private.capture_verification_documents();

-- Preserve any existing document references before removing them from the legacy row.
insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path)
select user_id,id,'national_id_front'::public.verification_document_type,id_front_path from public.verification_requests where id_front_path is not null
union all select user_id,id,'national_id_back'::public.verification_document_type,id_back_path from public.verification_requests where id_back_path is not null
union all select user_id,id,'face_scan'::public.verification_document_type,selfie_path from public.verification_requests where selfie_path is not null
union all select user_id,id,'driver_license_front'::public.verification_document_type,license_front_path from public.verification_requests where license_front_path is not null
union all select user_id,id,'driver_license_back'::public.verification_document_type,license_back_path from public.verification_requests where license_back_path is not null
on conflict(verification_request_id,document_type,version) do nothing;
update public.verification_requests set id_front_path=null,id_back_path=null,selfie_path=null,license_front_path=null,license_back_path=null where id_front_path is not null or id_back_path is not null or selfie_path is not null or license_front_path is not null or license_back_path is not null;

create or replace function public.assign_verification_reviewer(p_request_id uuid,p_reviewer_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin') then raise exception using errcode='42501',message='Administrator role required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=p_reviewer_id and role='reviewer') then raise exception using errcode='22023',message='Target user is not a reviewer.'; end if;
  if not exists(select 1 from public.verification_requests where id=p_request_id and status in ('submitted','in_review')) then raise exception using errcode='22023',message='Request is not reviewable.'; end if;
  insert into public.reviewer_assignments(reviewer_id,verification_request_id,assigned_by) values(p_reviewer_id,p_request_id,auth.uid()) on conflict(reviewer_id,verification_request_id) do update set assigned_at=pg_catalog.now() returning id into v_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'verification_reviewer_assigned','verification_request',p_request_id,jsonb_build_object('reviewer_id',p_reviewer_id)); return v_id;
end $$;
revoke all on function public.assign_verification_reviewer(uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_verification_reviewer(uuid,uuid) to authenticated;

create or replace function public.assign_vehicle_reviewer(p_vehicle_id uuid,p_reviewer_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$ declare v_id uuid; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin') then raise exception using errcode='42501',message='Administrator role required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=p_reviewer_id and role='reviewer') then raise exception using errcode='22023',message='Target user is not a reviewer.'; end if;
  if not exists(select 1 from public.vehicles where id=p_vehicle_id and status in ('submitted','in_review')) then raise exception using errcode='22023',message='Vehicle is not reviewable.'; end if;
  insert into public.reviewer_assignments(reviewer_id,vehicle_id,assigned_by) values(p_reviewer_id,p_vehicle_id,auth.uid()) on conflict(reviewer_id,vehicle_id) do update set assigned_at=pg_catalog.now() returning id into v_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'vehicle_reviewer_assigned','vehicle',p_vehicle_id,jsonb_build_object('reviewer_id',p_reviewer_id)); return v_id;
end $$;
revoke all on function public.assign_vehicle_reviewer(uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_vehicle_reviewer(uuid,uuid) to authenticated;

create or replace function public.review_verification_request(p_request_id uuid,p_decision public.verification_decision,p_notes text default null)
returns public.verification_status language plpgsql security definer set search_path=''
as $$ declare v public.verification_requests%rowtype; v_to public.verification_status; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  if not exists(select 1 from public.user_roles ur where ur.user_id=auth.uid() and ur.role in ('admin','reviewer')) then raise exception using errcode='42501',message='Reviewer or administrator role required.'; end if;
  select * into v from public.verification_requests where id=p_request_id for update;
  if not found then raise exception using errcode='P0002',message='Request not found.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin') and not exists(select 1 from public.reviewer_assignments where reviewer_id=auth.uid() and verification_request_id=p_request_id) then raise exception using errcode='42501',message='Request is not assigned to this reviewer.'; end if;
  v_to:=p_decision::text::public.verification_status;
  if not exists(select 1 from public.allowed_status_transitions where entity_type='verification' and from_status=v.status::text and to_status=v_to::text) then raise exception using errcode='22023',message='Invalid verification transition.'; end if;
  update public.verification_requests set status=v_to,reviewer_notes=p_notes where id=p_request_id;
  insert into public.verification_reviews(reviewer_id,verification_request_id,decision,reviewer_notes) values(auth.uid(),p_request_id,p_decision,p_notes);
  if v.user_role='driver' then
    insert into public.driver_profiles(user_id,verification_request_id,status,approved_at,approved_by)
    values(v.user_id,p_request_id,case p_decision when 'approved' then 'approved'::public.driver_profile_status when 'rejected' then 'rejected'::public.driver_profile_status else 'needs_resubmission'::public.driver_profile_status end,case when p_decision='approved' then pg_catalog.now() else null end,case when p_decision='approved' then auth.uid() else null end)
    on conflict(user_id) do update set verification_request_id=excluded.verification_request_id,status=excluded.status,approved_at=excluded.approved_at,approved_by=excluded.approved_by;
  end if;
  update public.profiles set verification_status=case p_decision when 'approved' then 'approved' when 'rejected' then 'rejected' else 'resubmission_required' end,role=case when v.user_role='driver' and p_decision='approved' then 'driver' else role end where id=v.user_id;
  if v.user_role='driver' and p_decision='approved' then insert into public.user_roles(user_id,role,assigned_by) values(v.user_id,'driver'::public.app_role,auth.uid()) on conflict(user_id,role) do nothing; end if;
  if v.user_role='driver' and p_decision='rejected' then delete from public.user_roles where user_id=v.user_id and role='driver'; end if;
  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'verification_decided','verification_request',p_request_id,jsonb_build_object('decision',p_decision::text,'user_role',v.user_role));
  return v_to;
end $$;
revoke all on function public.review_verification_request(uuid,public.verification_decision,text) from public,anon,authenticated;
grant execute on function public.review_verification_request(uuid,public.verification_decision,text) to authenticated;

create or replace function public.submit_vehicle_for_review(p_vehicle_id uuid)
returns public.vehicle_status language plpgsql security definer set search_path=''
as $$ declare v public.vehicles%rowtype; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  select * into v from public.vehicles where id=p_vehicle_id for update;
  if not found or v.owner_id<>auth.uid() then raise exception using errcode='42501',message='Vehicle not found or not owned by caller.'; end if;
  if not exists(select 1 from public.allowed_status_transitions where entity_type='vehicle' and from_status=v.status::text and to_status='submitted') then raise exception using errcode='22023',message='Vehicle cannot be submitted from current status.'; end if;
  if not exists(select 1 from public.vehicle_documents where vehicle_id=p_vehicle_id and document_type='vehicle_license_front') or not exists(select 1 from public.vehicle_documents where vehicle_id=p_vehicle_id and document_type='vehicle_license_back') then raise exception using errcode='22023',message='Both vehicle license sides are required.'; end if;
  update public.vehicles set status='submitted' where id=p_vehicle_id;
  insert into public.audit_log(actor_id,action,entity_type,entity_id) values(auth.uid(),'vehicle_submitted','vehicle',p_vehicle_id); return 'submitted'::public.vehicle_status;
end $$;
revoke all on function public.submit_vehicle_for_review(uuid) from public,anon,authenticated;
grant execute on function public.submit_vehicle_for_review(uuid) to authenticated;

create or replace function public.review_vehicle(p_vehicle_id uuid,p_decision public.verification_decision,p_notes text default null)
returns public.vehicle_status language plpgsql security definer set search_path=''
as $$ declare v public.vehicles%rowtype; v_to public.vehicle_status; begin
  if auth.uid() is null then raise exception using errcode='42501',message='Authentication required.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','reviewer')) then raise exception using errcode='42501',message='Reviewer or administrator role required.'; end if;
  select * into v from public.vehicles where id=p_vehicle_id for update;
  if not found then raise exception using errcode='P0002',message='Vehicle not found.'; end if;
  if not exists(select 1 from public.user_roles where user_id=auth.uid() and role='admin') and not exists(select 1 from public.reviewer_assignments where reviewer_id=auth.uid() and vehicle_id=p_vehicle_id) then raise exception using errcode='42501',message='Vehicle is not assigned to this reviewer.'; end if;
  v_to:=p_decision::text::public.vehicle_status;
  if not exists(select 1 from public.allowed_status_transitions where entity_type='vehicle' and from_status=v.status::text and to_status=v_to::text) then raise exception using errcode='22023',message='Invalid vehicle transition.'; end if;
  update public.vehicles set status=v_to,approved_at=case when v_to='approved' then pg_catalog.now() else null end,approved_by=case when v_to='approved' then auth.uid() else null end where id=p_vehicle_id;
  update public.vehicle_documents set status=case p_decision when 'approved' then 'accepted'::public.document_review_status when 'rejected' then 'rejected'::public.document_review_status else 'needs_resubmission'::public.document_review_status end where vehicle_id=p_vehicle_id;
  insert into public.verification_reviews(reviewer_id,vehicle_id,decision,reviewer_notes) values(auth.uid(),p_vehicle_id,p_decision,p_notes);
  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata) values(auth.uid(),'vehicle_decided','vehicle',p_vehicle_id,jsonb_build_object('decision',p_decision::text)); return v_to;
end $$;
revoke all on function public.review_vehicle(uuid,public.verification_decision,text) from public,anon,authenticated;
grant execute on function public.review_vehicle(uuid,public.verification_decision,text) to authenticated;

-- Audit records cannot be changed or removed through ordinary table access.
create or replace function private.prevent_audit_log_mutation()
returns trigger language plpgsql security invoker set search_path=''
as $$ begin raise exception using errcode='42501',message='Audit log rows are append-only.'; end $$;
revoke all on function private.prevent_audit_log_mutation() from public,anon,authenticated;
create trigger audit_log_no_update before update or delete on public.audit_log for each row execute function private.prevent_audit_log_mutation();

-- Storage buckets and exact object policies.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('vehicle-documents','vehicle-documents',false,10485760,array['image/jpeg','image/png','image/webp']),
 ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
create policy reviewer_read_assigned_identity_documents on storage.objects for select to authenticated using(bucket_id='identity-documents' and exists(select 1 from public.verification_documents d where d.storage_path=name and public.is_reviewer_for_verification(d.verification_request_id)));
create policy vehicle_docs_owner_read on storage.objects for select to authenticated using(bucket_id='vehicle-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy vehicle_docs_owner_upload on storage.objects for insert to authenticated with check(bucket_id='vehicle-documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy vehicle_docs_reviewer_read on storage.objects for select to authenticated using(bucket_id='vehicle-documents' and exists(select 1 from public.vehicle_documents d where d.storage_path=name and public.is_reviewer_for_vehicle(d.vehicle_id)));
create policy avatars_public_read on storage.objects for select to anon,authenticated using(bucket_id='avatars');
create policy avatars_owner_upload on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy avatars_owner_update on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy avatars_owner_delete on storage.objects for delete to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- Timestamp trigger for every new public table.
do $$ declare t record; begin
  for t in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') loop
    execute format('drop trigger if exists set_updated_at on public.%I',t.relname);
    execute format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t.relname);
  end loop;
end $$;

commit;
