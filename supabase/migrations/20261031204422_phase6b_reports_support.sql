-- Phase 6b: user reports, private report evidence, and support center.
begin;

do $$ begin create type public.emergency_incident_status as enum ('open','acknowledged','resolved'); exception when duplicate_object then null; end $$;
alter table public.emergency_incidents drop constraint if exists emergency_incidents_resolution_check;
alter table public.emergency_incidents drop constraint if exists emergency_incidents_status_check;
alter table public.emergency_incidents alter column status drop default;
alter table public.emergency_incidents alter column status type public.emergency_incident_status using status::public.emergency_incident_status;
alter table public.emergency_incidents alter column status set default 'open'::public.emergency_incident_status;
alter table public.emergency_incidents add constraint emergency_incidents_resolution_check
 check ((status='resolved')=(resolved_at is not null)) not valid;
alter table public.emergency_incidents validate constraint emergency_incidents_resolution_check;

do $$ begin create type public.report_status as enum ('open','under_review','resolved','dismissed'); exception when duplicate_object then null; end $$;
do $$ begin create type public.support_ticket_status as enum ('open','in_progress','resolved','closed'); exception when duplicate_object then null; end $$;

alter table public.allowed_status_transitions drop constraint if exists allowed_status_transitions_entity_type_check;
alter table public.allowed_status_transitions add constraint allowed_status_transitions_entity_type_check
 check(entity_type in ('verification','driver_profile','vehicle','trip','booking','deletion','emergency_incident','report','support_ticket'));

create table if not exists public.reports (
 id uuid primary key default extensions.gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete restrict,
 target_user_id uuid references public.profiles(id) on delete set null,
 trip_id uuid references public.trips(id) on delete set null,
 booking_id uuid references public.bookings(id) on delete set null,
 category text not null check(category in ('safety','harassment','fraud','trip_quality','identity','other')),
 description text not null check(length(pg_catalog.btrim(description)) between 10 and 5000),
 status public.report_status not null default 'open',
 resolution_note text,
 resolved_by uuid references public.profiles(id) on delete set null,
 resolved_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint reports_resolution_metadata_check check ((status in ('resolved','dismissed'))=(resolved_at is not null))
);
create index if not exists reports_reporter_created_idx on public.reports(reporter_id,created_at desc);
create index if not exists reports_target_created_idx on public.reports(target_user_id,created_at desc);
create index if not exists reports_trip_created_idx on public.reports(trip_id,created_at desc);
create index if not exists reports_status_created_idx on public.reports(status,created_at);

create table if not exists public.report_assignments (
 id uuid primary key default extensions.gen_random_uuid(),
 report_id uuid not null references public.reports(id) on delete cascade,
 reviewer_id uuid not null references public.profiles(id) on delete restrict,
 assigned_by uuid references public.profiles(id) on delete set null,
 assigned_at timestamptz not null default pg_catalog.now(),
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint report_assignments_report_reviewer_key unique(report_id,reviewer_id)
);
create index if not exists report_assignments_reviewer_idx on public.report_assignments(reviewer_id,assigned_at desc);
create index if not exists report_assignments_assigned_by_idx on public.report_assignments(assigned_by);

create table if not exists public.report_evidence (
 id uuid primary key default extensions.gen_random_uuid(),
 report_id uuid not null references public.reports(id) on delete cascade,
 uploaded_by uuid not null references public.profiles(id) on delete restrict,
 object_path text not null unique,
 mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp','video/mp4')),
 file_size_bytes bigint not null check(file_size_bytes between 1 and 10485760),
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint report_evidence_path_owner check(object_path like uploaded_by::text||'/'||report_id::text||'/%')
);
create index if not exists report_evidence_report_idx on public.report_evidence(report_id,created_at);

create table if not exists public.support_tickets (
 id uuid primary key default extensions.gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 category text not null check(category in ('account','verification','booking','trip','payment','safety','other')),
 subject text not null check(length(pg_catalog.btrim(subject)) between 3 and 160),
 description text not null check(length(pg_catalog.btrim(description)) between 10 and 5000),
 status public.support_ticket_status not null default 'open',
 assigned_to uuid references public.profiles(id) on delete set null,
 closed_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists support_tickets_user_created_idx on public.support_tickets(user_id,created_at desc);
create index if not exists support_tickets_status_created_idx on public.support_tickets(status,created_at);
create index if not exists support_tickets_assigned_idx on public.support_tickets(assigned_to,status);

create table if not exists public.support_messages (
 id uuid primary key default extensions.gen_random_uuid(),
 ticket_id uuid not null references public.support_tickets(id) on delete cascade,
 sender_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(length(pg_catalog.btrim(body)) between 1 and 5000),
 is_internal boolean not null default false,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists support_messages_ticket_created_idx on public.support_messages(ticket_id,created_at);
create index if not exists support_messages_sender_idx on public.support_messages(sender_id);

do $$ declare t text; begin
 foreach t in array array['reports','report_assignments','report_evidence','support_tickets','support_messages'] loop
  execute pg_catalog.format('alter table public.%I enable row level security',t);
  execute pg_catalog.format('revoke all on table public.%I from public,anon,authenticated',t);
 end loop;
end $$;
create trigger set_updated_at before update on public.reports for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.report_assignments for each row execute function public.set_updated_at();
create trigger set_updated_at before update on public.support_tickets for each row execute function public.set_updated_at();

grant select on public.reports to authenticated;
create policy reports_participant_read on public.reports for select to authenticated using(
 reporter_id=(select auth.uid()) or public.has_role('admin'::public.app_role)
 or exists(select 1 from public.report_assignments a where a.report_id=reports.id and a.reviewer_id=(select auth.uid()))
);
grant select on public.report_assignments to authenticated;
create policy report_assignments_assigned_read on public.report_assignments for select to authenticated using(reviewer_id=(select auth.uid()) or public.has_role('admin'::public.app_role));
grant select on public.report_evidence to authenticated;
create policy report_evidence_report_read on public.report_evidence for select to authenticated using(
 exists(select 1 from public.reports r where r.id=report_id and (
  r.reporter_id=(select auth.uid()) or public.has_role('admin'::public.app_role)
  or exists(select 1 from public.report_assignments a where a.report_id=r.id and a.reviewer_id=(select auth.uid()))
 ))
);

grant select,insert on public.support_tickets to authenticated;
create policy support_tickets_owner_or_staff_read on public.support_tickets for select to authenticated using(
 user_id=(select auth.uid()) or public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role)
);
create policy support_tickets_owner_insert on public.support_tickets for insert to authenticated with check(
 user_id=(select auth.uid()) and status='open' and assigned_to is null and closed_at is null
);
grant select on public.support_messages to authenticated;
create policy support_messages_owner_or_staff_read on public.support_messages for select to authenticated using(
 exists(select 1 from public.support_tickets t where t.id=ticket_id and (
  (t.user_id=(select auth.uid()) and is_internal=false)
  or public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role)
 ))
);

create or replace function public.create_support_ticket(p_category text,p_subject text,p_description text)
returns public.support_tickets
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_ticket public.support_tickets%rowtype;
begin
 if v_user is null then raise exception using errcode='42501',message='Login required.'; end if;
 insert into public.support_tickets(user_id,category,subject,description)
 values(v_user,p_category,pg_catalog.btrim(p_subject),pg_catalog.btrim(p_description)) returning * into v_ticket;
 insert into public.support_messages(ticket_id,sender_id,body,is_internal)
 values(v_ticket.id,v_user,pg_catalog.btrim(p_description),false);
 return v_ticket;
end $$;
revoke all on function public.create_support_ticket(text,text,text) from public,anon,authenticated;
grant execute on function public.create_support_ticket(text,text,text) to authenticated;

create or replace function public.add_support_message(p_ticket_id uuid,p_body text,p_is_internal boolean default false)
returns public.support_messages
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_ticket public.support_tickets%rowtype; v_message public.support_messages%rowtype; v_staff boolean;
begin
 if v_user is null or p_body is null or length(pg_catalog.btrim(p_body)) not between 1 and 5000 then raise exception using errcode='22023',message='Sign in and provide a valid message.'; end if;
 v_staff:=public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role);
 select * into v_ticket from public.support_tickets where id=p_ticket_id for update;
 if not found or (v_ticket.user_id<>v_user and not v_staff) then raise exception using errcode='42501',message='Ticket not found or not accessible.'; end if;
 if p_is_internal and not v_staff then raise exception using errcode='42501',message='Only support staff can create internal notes.'; end if;
 if v_ticket.status in ('resolved','closed') and not v_staff then raise exception using errcode='22023',message='This ticket is closed.'; end if;
 insert into public.support_messages(ticket_id,sender_id,body,is_internal)
 values(p_ticket_id,v_user,pg_catalog.btrim(p_body),p_is_internal) returning * into v_message;
 if v_ticket.status='open' and v_staff then update public.support_tickets set status='in_progress',assigned_to=coalesce(assigned_to,v_user) where id=p_ticket_id; end if;
 return v_message;
end $$;
revoke all on function public.add_support_message(uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.add_support_message(uuid,text,boolean) to authenticated;

create or replace function public.close_own_support_ticket(p_ticket_id uuid)
returns boolean
language plpgsql security definer set search_path=''
as $$
begin
 update public.support_tickets set status='closed',closed_at=pg_catalog.now()
 where id=p_ticket_id and user_id=auth.uid() and status in ('open','in_progress');
 return found;
end $$;
revoke all on function public.close_own_support_ticket(uuid) from public,anon,authenticated;
grant execute on function public.close_own_support_ticket(uuid) to authenticated;

insert into public.allowed_status_transitions(entity_type,from_status,to_status,actor_role)
select v.entity_type,v.from_status,v.to_status,v.actor_role::public.app_role
from (values
 ('emergency_incident','open','acknowledged','reviewer'),
 ('emergency_incident','open','resolved','admin'),
 ('emergency_incident','acknowledged','resolved','admin'),
 ('report','open','under_review','reviewer'),
 ('report','open','resolved','admin'),
 ('report','open','dismissed','admin'),
 ('report','under_review','resolved','admin'),
 ('report','under_review','dismissed','admin'),
 ('report','under_review','open','reviewer'),
 ('support_ticket','open','in_progress','reviewer'),
 ('support_ticket','open','closed','rider'),
 ('support_ticket','in_progress','resolved','reviewer'),
 ('support_ticket','in_progress','closed','rider'),
 ('support_ticket','resolved','closed','rider'),
 ('support_ticket','resolved','in_progress','reviewer')
) v(entity_type,from_status,to_status,actor_role)
where not exists(select 1 from public.allowed_status_transitions a where a.entity_type=v.entity_type
 and a.from_status=v.from_status and a.to_status=v.to_status and a.actor_role is not distinct from v.actor_role::public.app_role);

create trigger emergency_incidents_workflow_guard before update of status on public.emergency_incidents for each row execute function public.enforce_workflow_transition('emergency_incident');
create trigger reports_workflow_guard before update of status on public.reports for each row execute function public.enforce_workflow_transition('report');
create trigger reports_workflow_audit after update of status on public.reports for each row execute function public.log_workflow_transition('report');
create trigger support_tickets_workflow_guard before update of status on public.support_tickets for each row execute function public.enforce_workflow_transition('support_ticket');

-- Supabase Storage bucket creation/configuration via SQL.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('report-evidence','report-evidence',false,10485760,array['image/jpeg','image/png','image/webp','video/mp4'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists report_evidence_owner_upload on storage.objects;
create policy report_evidence_owner_upload on storage.objects for insert to authenticated with check(
 bucket_id='report-evidence' and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists(select 1 from public.reports r where r.id::text=(storage.foldername(name))[2] and r.reporter_id=(select auth.uid()) and r.status='open')
);
drop policy if exists report_evidence_participant_read on storage.objects;
create policy report_evidence_participant_read on storage.objects for select to authenticated using(
 bucket_id='report-evidence' and exists(
  select 1 from public.report_evidence e join public.reports r on r.id=e.report_id
  where e.object_path=name and (r.reporter_id=(select auth.uid()) or public.has_role('admin'::public.app_role)
   or exists(select 1 from public.report_assignments a where a.report_id=r.id and a.reviewer_id=(select auth.uid())))
 )
);
drop policy if exists report_evidence_owner_delete on storage.objects;
create policy report_evidence_owner_delete on storage.objects for delete to authenticated using(
 bucket_id='report-evidence' and (storage.foldername(name))[1]=(select auth.uid())::text
 and exists(select 1 from public.report_evidence e join public.reports r on r.id=e.report_id where e.object_path=name and r.reporter_id=(select auth.uid()) and r.status='open')
);

create or replace function public.create_report(
 p_category text,p_description text,p_trip_id uuid default null,p_booking_id uuid default null,p_target_user_id uuid default null
)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_trip_id uuid:=p_trip_id; v_booking public.bookings%rowtype; v_trip public.trips%rowtype; v_id uuid;
begin
 if v_user is null or p_category not in ('safety','harassment','fraud','trip_quality','identity','other')
   or p_description is null or length(pg_catalog.btrim(p_description)) not between 10 and 5000 then
  raise exception using errcode='22023',message='Valid report details and sign-in are required.';
 end if;
 if p_booking_id is not null then
  select * into v_booking from public.bookings where id=p_booking_id;
  if not found then raise exception using errcode='P0002',message='Booking not found.'; end if;
  v_trip_id:=v_booking.trip_id;
 end if;
 if v_trip_id is not null then
  select * into v_trip from public.trips where id=v_trip_id;
  if not found then raise exception using errcode='P0002',message='Trip not found.'; end if;
  if v_user<>v_trip.driver_id and not exists(select 1 from public.bookings b where b.trip_id=v_trip_id and b.passenger_id=v_user) then
   raise exception using errcode='42501',message='Only a trip participant can report this trip.';
  end if;
 end if;
 if p_target_user_id is not null and (v_trip_id is null or
   (p_target_user_id<>v_trip.driver_id and not exists(select 1 from public.bookings b where b.trip_id=v_trip_id and b.passenger_id=p_target_user_id))) then
  raise exception using errcode='42501',message='Reported user must be part of the related trip.';
 end if;
 insert into public.reports(reporter_id,target_user_id,trip_id,booking_id,category,description)
 values(v_user,p_target_user_id,v_trip_id,p_booking_id,p_category,pg_catalog.btrim(p_description))
 returning id into v_id;
 return v_id;
end $$;
revoke all on function public.create_report(text,text,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.create_report(text,text,uuid,uuid,uuid) to authenticated;

create or replace function public.add_report_evidence(p_report_id uuid,p_object_path text,p_mime_type text,p_file_size_bytes bigint)
returns public.report_evidence
language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_row public.report_evidence%rowtype;
begin
 if v_user is null or p_object_path not like v_user::text||'/'||p_report_id::text||'/%' then raise exception using errcode='42501',message='Evidence path must belong to this report and user.'; end if;
 if not exists(select 1 from public.reports r where r.id=p_report_id and r.reporter_id=v_user and r.status='open')
  or not exists(select 1 from storage.objects o where o.bucket_id='report-evidence' and o.name=p_object_path) then
  raise exception using errcode='42501',message='Report or uploaded evidence not found.';
 end if;
 insert into public.report_evidence(report_id,uploaded_by,object_path,mime_type,file_size_bytes)
 values(p_report_id,v_user,p_object_path,p_mime_type,p_file_size_bytes) returning * into v_row;
 return v_row;
end $$;
revoke all on function public.add_report_evidence(uuid,text,text,bigint) from public,anon,authenticated;
grant execute on function public.add_report_evidence(uuid,text,text,bigint) to authenticated;

commit;
