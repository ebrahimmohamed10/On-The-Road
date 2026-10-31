-- Phase 7: simulated cash ledger, platform administration, organizations, and retention work queues.
begin;

do $$ begin create type public.simulated_payment_status as enum ('cash_due','cash_received','refund_requested','refund_simulated','voided'); exception when duplicate_object then null; end $$;
do $$ begin create type public.refund_request_status as enum ('open','approved','rejected','simulated'); exception when duplicate_object then null; end $$;

alter table public.emergency_incidents
 add column if not exists resolved_by uuid references public.profiles(id) on delete set null,
 add column if not exists resolution_note text;
create index if not exists emergency_incidents_resolved_by_idx on public.emergency_incidents(resolved_by);

alter table public.allowed_status_transitions drop constraint if exists allowed_status_transitions_entity_type_check;
alter table public.allowed_status_transitions add constraint allowed_status_transitions_entity_type_check
 check(entity_type in ('verification','driver_profile','vehicle','trip','booking','deletion','emergency_incident','report','support_ticket','payment','refund_request'));

insert into public.allowed_status_transitions(entity_type,from_status,to_status,actor_role)
select v.entity_type,v.from_status,v.to_status,v.actor_role::public.app_role
from (values
 ('payment','cash_due','cash_received','driver'),
 ('payment','cash_due','voided',null),
 ('payment','cash_received','refund_requested','rider'),
 ('payment','refund_requested','refund_simulated','admin'),
 ('payment','refund_requested','cash_received','admin'),
 ('refund_request','open','approved','admin'),
 ('refund_request','open','rejected','admin'),
 ('refund_request','approved','simulated','admin'),
 ('deletion','requested','processing','admin'),
 ('deletion','requested','rejected','admin'),
 ('deletion','processing','completed','admin'),
 ('deletion','processing','rejected','admin')
) v(entity_type,from_status,to_status,actor_role)
where not exists(select 1 from public.allowed_status_transitions a where a.entity_type=v.entity_type
 and a.from_status=v.from_status and a.to_status=v.to_status and a.actor_role is not distinct from v.actor_role::public.app_role);

create table if not exists public.simulated_payments (
 id uuid primary key default extensions.gen_random_uuid(),
 booking_id uuid not null unique references public.bookings(id) on delete restrict,
 payer_id uuid not null references public.profiles(id) on delete restrict,
 payee_id uuid not null references public.profiles(id) on delete restrict,
 amount_minor bigint not null check(amount_minor>=0),
 currency char(3) not null default 'EGP' check(currency='EGP'),
 status public.simulated_payment_status not null default 'cash_due',
 cash_reported_by uuid references public.profiles(id) on delete set null,
 cash_reported_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint simulated_payments_different_participants check(payer_id<>payee_id),
 constraint simulated_payments_cash_metadata_check check((status in ('cash_received','refund_requested','refund_simulated'))=(cash_reported_at is not null and cash_reported_by is not null))
);
create index if not exists simulated_payments_payer_created_idx on public.simulated_payments(payer_id,created_at desc);
create index if not exists simulated_payments_payee_created_idx on public.simulated_payments(payee_id,created_at desc);
create index if not exists simulated_payments_booking_idx on public.simulated_payments(booking_id);

create table if not exists public.refund_requests (
 id uuid primary key default extensions.gen_random_uuid(),
 simulated_payment_id uuid not null references public.simulated_payments(id) on delete restrict,
 requester_id uuid not null references public.profiles(id) on delete restrict,
 amount_minor bigint not null check(amount_minor>=0),
 reason text not null check(length(pg_catalog.btrim(reason)) between 5 and 2000),
 status public.refund_request_status not null default 'open',
 decision_note text,
 decided_by uuid references public.profiles(id) on delete set null,
 decided_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint refund_requests_decision_metadata_check check((status in ('approved','rejected','simulated'))=(decided_at is not null))
);
create index if not exists refund_requests_payment_idx on public.refund_requests(simulated_payment_id);
create index if not exists refund_requests_requester_idx on public.refund_requests(requester_id,created_at desc);
create index if not exists refund_requests_status_idx on public.refund_requests(status,created_at);

create table if not exists public.simulated_payment_events (
 id uuid primary key default extensions.gen_random_uuid(),
 simulated_payment_id uuid not null references public.simulated_payments(id) on delete restrict,
 actor_id uuid references public.profiles(id) on delete set null,
 event_type text not null check(event_type in ('cash_due_created','cash_received_reported','refund_requested','refund_approved','refund_rejected','refund_simulated','payment_voided')),
 details jsonb not null default '{}'::jsonb,
 occurred_at timestamptz not null default pg_catalog.now(),
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists simulated_payment_events_payment_time_idx on public.simulated_payment_events(simulated_payment_id,occurred_at);
create index if not exists simulated_payment_events_actor_idx on public.simulated_payment_events(actor_id);

create table if not exists public.organizations (
 id uuid primary key default extensions.gen_random_uuid(),
 name text not null check(length(pg_catalog.btrim(name)) between 2 and 160),
 organization_type text not null check(organization_type in ('transport_operator','university','employer','other')),
 status text not null default 'active' check(status in ('active','suspended','closed')),
 created_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists organizations_status_created_idx on public.organizations(status,created_at);

create table if not exists public.organization_members (
 id uuid primary key default extensions.gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 member_role text not null check(member_role in ('owner','dispatcher','viewer')),
 invited_by uuid references public.profiles(id) on delete set null,
 joined_at timestamptz,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint organization_members_org_user_key unique(organization_id,user_id)
);
create index if not exists organization_members_user_idx on public.organization_members(user_id,organization_id);
create index if not exists organization_members_inviter_idx on public.organization_members(invited_by);

create table if not exists public.admin_actions (
 id uuid primary key default extensions.gen_random_uuid(),
 actor_id uuid references public.profiles(id) on delete set null,
 action text not null check(length(pg_catalog.btrim(action)) between 2 and 120),
 target_type text,
 target_id uuid,
 details jsonb not null default '{}'::jsonb,
 occurred_at timestamptz not null default pg_catalog.now(),
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists admin_actions_actor_time_idx on public.admin_actions(actor_id,occurred_at desc);
create index if not exists admin_actions_target_idx on public.admin_actions(target_type,target_id,occurred_at desc);

create table if not exists public.account_deletion_jobs (
 id uuid primary key default extensions.gen_random_uuid(),
 request_id uuid not null unique,
 user_id uuid not null,
 operation text not null check(operation in ('disable_auth_user','delete_auth_user')),
 status text not null default 'pending' check(status in ('pending','processing','completed','failed')),
 attempts integer not null default 0 check(attempts>=0),
 available_at timestamptz not null default pg_catalog.now(),
 last_error text,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now()
);
create index if not exists account_deletion_jobs_pending_idx on public.account_deletion_jobs(available_at,created_at) where status in ('pending','failed');

create table if not exists public.storage_deletion_jobs (
 id uuid primary key default extensions.gen_random_uuid(),
 bucket_id text not null,
 object_path text not null,
 delete_after timestamptz not null,
 status text not null default 'pending' check(status in ('pending','processing','completed','failed')),
 attempts integer not null default 0 check(attempts>=0),
 last_error text,
 created_at timestamptz not null default pg_catalog.now(),
 updated_at timestamptz not null default pg_catalog.now(),
 constraint storage_deletion_object_key unique(bucket_id,object_path)
);
create index if not exists storage_deletion_jobs_due_idx on public.storage_deletion_jobs(delete_after,created_at) where status in ('pending','failed');

do $$ declare t text; begin
 foreach t in array array['simulated_payments','refund_requests','simulated_payment_events','organizations','organization_members','admin_actions','account_deletion_jobs','storage_deletion_jobs'] loop
  execute pg_catalog.format('alter table public.%I enable row level security',t);
  execute pg_catalog.format('revoke all on table public.%I from public,anon,authenticated',t);
  execute pg_catalog.format('create trigger set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t);
 end loop;
end $$;

grant select on public.simulated_payments to authenticated;
create policy simulated_payment_participant_read on public.simulated_payments for select to authenticated using(payer_id=(select auth.uid()) or payee_id=(select auth.uid()) or public.has_role('admin'::public.app_role));
grant select on public.refund_requests to authenticated;
create policy refund_request_participant_read on public.refund_requests for select to authenticated using(
 requester_id=(select auth.uid()) or exists(select 1 from public.simulated_payments p where p.id=simulated_payment_id and p.payee_id=(select auth.uid())) or public.has_role('admin'::public.app_role)
);
grant select on public.simulated_payment_events to authenticated;
create policy simulated_payment_events_participant_read on public.simulated_payment_events for select to authenticated using(
 exists(select 1 from public.simulated_payments p where p.id=simulated_payment_id and (p.payer_id=(select auth.uid()) or p.payee_id=(select auth.uid()) or public.has_role('admin'::public.app_role)))
);

grant select on public.organizations,public.organization_members to authenticated;
create policy organization_membership_self_read on public.organization_members for select to authenticated using(user_id=(select auth.uid()) or public.has_role('admin'::public.app_role));
create policy organizations_member_read on public.organizations for select to authenticated using(
 public.has_role('admin'::public.app_role) or exists(select 1 from public.organization_members m where m.organization_id=id and m.user_id=(select auth.uid()))
);
grant select on public.admin_actions to authenticated;
create policy admin_actions_admin_read on public.admin_actions for select to authenticated using(public.has_role('admin'::public.app_role));

grant select,update on public.account_deletion_jobs,public.storage_deletion_jobs to service_role;
revoke insert on public.account_deletion_requests from authenticated;

create trigger simulated_payments_workflow_guard before update of status on public.simulated_payments
 for each row execute function public.enforce_workflow_transition('payment');
create trigger simulated_payments_workflow_audit after update of status on public.simulated_payments
 for each row execute function public.log_workflow_transition('payment');
create trigger refund_requests_workflow_guard before update of status on public.refund_requests
 for each row execute function public.enforce_workflow_transition('refund_request');
create trigger refund_requests_workflow_audit after update of status on public.refund_requests
 for each row execute function public.log_workflow_transition('refund_request');
create trigger account_deletion_workflow_guard before update of status on public.account_deletion_requests
 for each row execute function public.enforce_workflow_transition('deletion');
create trigger account_deletion_workflow_audit after update of status on public.account_deletion_requests
 for each row execute function public.log_workflow_transition('account_deletion_request');

insert into public.simulated_payments(booking_id,payer_id,payee_id,amount_minor)
select b.id,b.passenger_id,t.driver_id,b.total_price_minor
from public.bookings b join public.trips t on t.id=b.trip_id
where b.status='confirmed'
on conflict(booking_id) do nothing;
insert into public.simulated_payment_events(simulated_payment_id,event_type,details)
select p.id,'cash_due_created',jsonb_build_object('mode','cash_simulated')
from public.simulated_payments p
on conflict do nothing;

create or replace function public.create_cash_due_for_confirmed_booking()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_driver uuid;
begin
 if new.status='confirmed' and (tg_op='INSERT' or old.status is distinct from new.status) then
  select driver_id into v_driver from public.trips where id=new.trip_id;
  insert into public.simulated_payments(booking_id,payer_id,payee_id,amount_minor)
  values(new.id,new.passenger_id,v_driver,new.total_price_minor) on conflict(booking_id) do nothing;
 elsif new.status='cancelled' and old.status is distinct from new.status then
  update public.simulated_payments set status='voided' where booking_id=new.id and status='cash_due';
 end if;
 return new;
end $$;
revoke all on function public.create_cash_due_for_confirmed_booking() from public,anon,authenticated;
create trigger booking_cash_payment_sync after insert or update of status on public.bookings
 for each row execute function public.create_cash_due_for_confirmed_booking();

create or replace function public.log_simulated_payment_event()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_event text;
begin
 if tg_op='INSERT' then v_event:='cash_due_created';
 else
  if old.status is not distinct from new.status then return new; end if;
  v_event:=case new.status when 'cash_received' then 'cash_received_reported' when 'refund_requested' then 'refund_requested'
   when 'refund_simulated' then 'refund_simulated' when 'voided' then 'payment_voided' else 'cash_due_created' end;
 end if;
 insert into public.simulated_payment_events(simulated_payment_id,actor_id,event_type,details)
 values(new.id,auth.uid(),v_event,jsonb_build_object('status',new.status::text,'amount_minor',new.amount_minor));
 return new;
end $$;
revoke all on function public.log_simulated_payment_event() from public,anon,authenticated;
create trigger simulated_payment_event_log after insert or update of status on public.simulated_payments
 for each row execute function public.log_simulated_payment_event();

create or replace function public.audit_admin_action(p_action text,p_target_type text,p_target_id uuid,p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=''
as $$
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 insert into public.admin_actions(actor_id,action,target_type,target_id,details)
 values(auth.uid(),p_action,p_target_type,p_target_id,coalesce(p_details,'{}'::jsonb));
 insert into public.audit_log(actor_id,action,entity_type,entity_id,occurred_at,metadata)
 values(auth.uid(),p_action,p_target_type,p_target_id,pg_catalog.now(),coalesce(p_details,'{}'::jsonb));
end $$;
revoke all on function public.audit_admin_action(text,text,uuid,jsonb) from public,anon,authenticated;

create or replace function public.assign_user_role(p_user_id uuid,p_role public.app_role,p_grant boolean)
returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 if not exists(select 1 from public.profiles where id=p_user_id) then raise exception using errcode='P0002',message='User not found.'; end if;
 if p_role='rider' and not p_grant then raise exception using errcode='22023',message='Every account retains the rider role.'; end if;
 if p_role='driver' and p_grant and not exists(select 1 from public.driver_profiles where user_id=p_user_id and status='approved') then
  raise exception using errcode='22023',message='Only approved drivers can be assigned the driver role.';
 end if;
 if p_role='admin' and not p_grant and (select count(*) from public.user_roles where role='admin')<=1 then
  raise exception using errcode='22023',message='The last administrator cannot be removed.';
 end if;
 if p_grant then
  insert into public.user_roles(user_id,role,assigned_by) values(p_user_id,p_role,auth.uid()) on conflict(user_id,role) do nothing;
 else delete from public.user_roles where user_id=p_user_id and role=p_role;
 end if;
 perform public.audit_admin_action(case when p_grant then 'role_granted' else 'role_revoked' end,'user',p_user_id,jsonb_build_object('role',p_role::text));
 return true;
end $$;
revoke all on function public.assign_user_role(uuid,public.app_role,boolean) from public,anon,authenticated;
grant execute on function public.assign_user_role(uuid,public.app_role,boolean) to authenticated;

create or replace function public.set_app_setting(p_key text,p_value jsonb)
returns public.app_settings language plpgsql security definer set search_path=''
as $$
declare v_row public.app_settings%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 select * into v_row from public.app_settings where key=p_key for update;
 if not found then raise exception using errcode='P0002',message='Setting not found.'; end if;
 if jsonb_typeof(v_row.value)<>jsonb_typeof(p_value) then raise exception using errcode='22023',message='Setting value type cannot change.'; end if;
 update public.app_settings set value=p_value,updated_by=auth.uid() where key=p_key returning * into v_row;
 perform public.audit_admin_action('setting_updated','app_setting',null,jsonb_build_object('key',p_key));
 return v_row;
end $$;
revoke all on function public.set_app_setting(text,jsonb) from public,anon,authenticated;
grant execute on function public.set_app_setting(text,jsonb) to authenticated;

create or replace function public.assign_report_reviewer(p_report_id uuid,p_reviewer_id uuid)
returns public.report_assignments language plpgsql security definer set search_path=''
as $$
declare v_row public.report_assignments%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 if not exists(select 1 from public.user_roles where user_id=p_reviewer_id and role='reviewer') then raise exception using errcode='22023',message='Selected account is not a reviewer.'; end if;
 insert into public.report_assignments(report_id,reviewer_id,assigned_by) values(p_report_id,p_reviewer_id,auth.uid())
 on conflict(report_id,reviewer_id) do update set assigned_by=excluded.assigned_by returning * into v_row;
 update public.reports set status='under_review' where id=p_report_id and status='open';
 perform public.audit_admin_action('report_reviewer_assigned','report',p_report_id,jsonb_build_object('reviewer_id',p_reviewer_id));
 return v_row;
end $$;
revoke all on function public.assign_report_reviewer(uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_report_reviewer(uuid,uuid) to authenticated;

create or replace function public.resolve_report(p_report_id uuid,p_status public.report_status,p_note text default null)
returns public.reports language plpgsql security definer set search_path=''
as $$
declare v_report public.reports%rowtype; v_actor uuid:=auth.uid(); v_admin boolean:=public.has_role('admin'::public.app_role);
begin
 if v_actor is null or p_status not in ('under_review','resolved','dismissed') then raise exception using errcode='22023',message='Invalid review decision.'; end if;
 select * into v_report from public.reports where id=p_report_id for update;
 if not found then raise exception using errcode='P0002',message='Report not found.'; end if;
 if not v_admin and (not public.has_role('reviewer'::public.app_role) or not exists(select 1 from public.report_assignments a where a.report_id=p_report_id and a.reviewer_id=v_actor)) then
  raise exception using errcode='42501',message='Assigned reviewer or administrator role required.';
 end if;
 if p_status in ('resolved','dismissed') and not v_admin then raise exception using errcode='42501',message='Only administrators can close a report.'; end if;
 update public.reports set status=p_status,resolution_note=nullif(pg_catalog.btrim(p_note),''),
  resolved_by=case when p_status in ('resolved','dismissed') then v_actor else null end,
  resolved_at=case when p_status in ('resolved','dismissed') then pg_catalog.now() else null end
 where id=p_report_id returning * into v_report;
 if v_admin then perform public.audit_admin_action('report_decided','report',p_report_id,jsonb_build_object('status',p_status::text)); end if;
 return v_report;
end $$;
revoke all on function public.resolve_report(uuid,public.report_status,text) from public,anon,authenticated;
grant execute on function public.resolve_report(uuid,public.report_status,text) to authenticated;

create or replace function public.resolve_emergency_incident(p_incident_id uuid,p_status public.emergency_incident_status,p_note text default null)
returns public.emergency_incidents language plpgsql security definer set search_path=''
as $$
declare v_row public.emergency_incidents%rowtype; v_actor uuid:=auth.uid();
begin
 if v_actor is null or not (public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role))
  or p_status not in ('acknowledged','resolved') then raise exception using errcode='42501',message='Support staff and a valid status are required.'; end if;
 select * into v_row from public.emergency_incidents where id=p_incident_id for update;
 if not found then raise exception using errcode='P0002',message='Incident not found.'; end if;
 if p_status='resolved' and not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Only an administrator can resolve an incident.'; end if;
 update public.emergency_incidents set status=p_status,resolved_at=case when p_status='resolved' then pg_catalog.now() else null end,
  resolved_by=case when p_status='resolved' then v_actor else null end,
  resolution_note=nullif(pg_catalog.btrim(p_note),'') where id=p_incident_id returning * into v_row;
 if public.has_role('admin'::public.app_role) then perform public.audit_admin_action('emergency_incident_decided','emergency_incident',p_incident_id,jsonb_build_object('status',p_status::text)); end if;
 return v_row;
end $$;
revoke all on function public.resolve_emergency_incident(uuid,public.emergency_incident_status,text) from public,anon,authenticated;
grant execute on function public.resolve_emergency_incident(uuid,public.emergency_incident_status,text) to authenticated;

create or replace function public.resolve_support_ticket(p_ticket_id uuid,p_note text default null)
returns public.support_tickets language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_row public.support_tickets%rowtype;
begin
 if v_user is null or not (public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role)) then raise exception using errcode='42501',message='Support staff role required.'; end if;
 update public.support_tickets set status='resolved',assigned_to=coalesce(assigned_to,v_user),closed_at=pg_catalog.now()
 where id=p_ticket_id and status in ('open','in_progress') returning * into v_row;
 if not found then raise exception using errcode='P0002',message='Open support ticket not found.'; end if;
 if public.has_role('admin'::public.app_role) then perform public.audit_admin_action('support_ticket_resolved','support_ticket',p_ticket_id,jsonb_build_object('note',nullif(pg_catalog.btrim(p_note),''))); end if;
 return v_row;
end $$;
revoke all on function public.resolve_support_ticket(uuid,text) from public,anon,authenticated;
grant execute on function public.resolve_support_ticket(uuid,text) to authenticated;

create or replace function public.create_organization(p_name text,p_type text,p_owner_id uuid)
returns public.organizations language plpgsql security definer set search_path=''
as $$
declare v_org public.organizations%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 insert into public.organizations(name,organization_type,created_by) values(pg_catalog.btrim(p_name),p_type,auth.uid()) returning * into v_org;
 insert into public.organization_members(organization_id,user_id,member_role,invited_by,joined_at)
 values(v_org.id,p_owner_id,'owner',auth.uid(),pg_catalog.now());
 perform public.audit_admin_action('organization_created','organization',v_org.id,jsonb_build_object('type',p_type));
 return v_org;
end $$;
revoke all on function public.create_organization(text,text,uuid) from public,anon,authenticated;
grant execute on function public.create_organization(text,text,uuid) to authenticated;

create or replace function public.request_account_deletion()
returns public.account_deletion_requests language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_row public.account_deletion_requests%rowtype;
begin
 if v_user is null then raise exception using errcode='42501',message='Login required.'; end if;
 insert into public.account_deletion_requests(user_id) values(v_user) returning * into v_row;
 return v_row;
end $$;
revoke all on function public.request_account_deletion() from public,anon,authenticated;
grant execute on function public.request_account_deletion() to authenticated;

create or replace function public.review_account_deletion_request(p_request_id uuid,p_approve boolean,p_note text default null)
returns public.account_deletion_requests language plpgsql security definer set search_path=''
as $$
declare v_row public.account_deletion_requests%rowtype; v_next public.account_deletion_status;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 select * into v_row from public.account_deletion_requests where id=p_request_id for update;
 if not found or v_row.status<>'requested' then raise exception using errcode='P0002',message='Pending deletion request not found.'; end if;
 v_next:=case when p_approve then 'processing'::public.account_deletion_status else 'rejected'::public.account_deletion_status end;
 update public.account_deletion_requests set status=v_next,processed_at=case when p_approve then null else pg_catalog.now() end where id=p_request_id returning * into v_row;
 if p_approve then
  insert into public.account_deletion_jobs(request_id,user_id,operation) values(v_row.id,v_row.user_id,'disable_auth_user');
  insert into public.storage_deletion_jobs(bucket_id,object_path,delete_after)
   select 'identity-documents',d.storage_path,pg_catalog.now()+interval '12 months' from public.verification_documents d where d.user_id=v_row.user_id
   union select 'vehicle-documents',d.storage_path,pg_catalog.now()+interval '12 months' from public.vehicle_documents d where d.user_id=v_row.user_id
   union select 'avatars',p.avatar_path,pg_catalog.now() from public.profiles p where p.id=v_row.user_id and p.avatar_path is not null
  on conflict(bucket_id,object_path) do nothing;
 end if;
 perform public.audit_admin_action(case when p_approve then 'account_deletion_queued' else 'account_deletion_rejected' end,'account_deletion_request',p_request_id,jsonb_build_object('note',nullif(pg_catalog.btrim(p_note),'')));
 return v_row;
end $$;
revoke all on function public.review_account_deletion_request(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.review_account_deletion_request(uuid,boolean,text) to authenticated;

create or replace function public.transition_account_deletion_job(p_job_id uuid,p_status text,p_error text default null)
returns boolean language plpgsql security definer set search_path=''
as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception using errcode='42501',message='Service role required.'; end if;
 if p_status not in ('processing','completed','failed') then raise exception using errcode='22023',message='Invalid job status.'; end if;
 update public.account_deletion_jobs set status=p_status,attempts=attempts+case when p_status='failed' then 1 else 0 end,
  available_at=case when p_status='failed' then pg_catalog.now()+interval '15 minutes' else available_at end,last_error=p_error
 where id=p_job_id;
 return found;
end $$;
revoke all on function public.transition_account_deletion_job(uuid,text,text) from public,anon,authenticated;
grant execute on function public.transition_account_deletion_job(uuid,text,text) to service_role;

create or replace function public.record_cash_received(p_booking_id uuid)
returns public.simulated_payments language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_payment public.simulated_payments%rowtype;
begin
 if v_user is null or not public.has_role('driver'::public.app_role) then raise exception using errcode='42501',message='Trip driver login is required.'; end if;
 select p.* into v_payment from public.simulated_payments p join public.bookings b on b.id=p.booking_id
 join public.trips t on t.id=b.trip_id where b.id=p_booking_id and t.driver_id=v_user and b.status in ('confirmed','completed') for update of p;
 if not found or v_payment.status<>'cash_due' then raise exception using errcode='22023',message='No cash due is available for this booking.'; end if;
 update public.simulated_payments set status='cash_received',cash_reported_by=v_user,cash_reported_at=pg_catalog.now()
 where id=v_payment.id returning * into v_payment;
 return v_payment;
end $$;
revoke all on function public.record_cash_received(uuid) from public,anon,authenticated;
grant execute on function public.record_cash_received(uuid) to authenticated;

create or replace function public.request_simulated_refund(p_booking_id uuid,p_reason text)
returns public.refund_requests language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_payment public.simulated_payments%rowtype; v_request public.refund_requests%rowtype;
begin
 if v_user is null or p_reason is null or length(pg_catalog.btrim(p_reason)) not between 5 and 2000 then raise exception using errcode='22023',message='Sign in and provide a refund reason.'; end if;
 select p.* into v_payment from public.simulated_payments p join public.bookings b on b.id=p.booking_id
 where b.id=p_booking_id and b.passenger_id=v_user and b.status='cancelled' for update of p;
 if not found or v_payment.status<>'cash_received' then raise exception using errcode='22023',message='Only cash already marked received on a cancelled booking can be reviewed.'; end if;
 insert into public.refund_requests(simulated_payment_id,requester_id,amount_minor,reason)
 values(v_payment.id,v_user,v_payment.amount_minor,pg_catalog.btrim(p_reason)) returning * into v_request;
 update public.simulated_payments set status='refund_requested' where id=v_payment.id;
 return v_request;
end $$;
revoke all on function public.request_simulated_refund(uuid,text) from public,anon,authenticated;
grant execute on function public.request_simulated_refund(uuid,text) to authenticated;

create or replace function public.review_simulated_refund(p_refund_request_id uuid,p_approve boolean,p_note text default null)
returns public.refund_requests language plpgsql security definer set search_path=''
as $$
declare v_row public.refund_requests%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 select * into v_row from public.refund_requests where id=p_refund_request_id for update;
 if not found or v_row.status<>'open' then raise exception using errcode='P0002',message='Open refund request not found.'; end if;
 update public.refund_requests set status=case when p_approve then 'approved'::public.refund_request_status else 'rejected'::public.refund_request_status end,
  decided_by=auth.uid(),decided_at=pg_catalog.now(),decision_note=nullif(pg_catalog.btrim(p_note),'')
 where id=p_refund_request_id returning * into v_row;
 if not p_approve then
  update public.simulated_payments set status='cash_received' where id=v_row.simulated_payment_id and status='refund_requested';
 end if;
 perform public.audit_admin_action(case when p_approve then 'refund_approved' else 'refund_rejected' end,'refund_request',p_refund_request_id,'{}'::jsonb);
 return v_row;
end $$;
revoke all on function public.review_simulated_refund(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.review_simulated_refund(uuid,boolean,text) to authenticated;

create or replace function public.mark_refund_simulated(p_refund_request_id uuid,p_note text default null)
returns public.refund_requests language plpgsql security definer set search_path=''
as $$
declare v_row public.refund_requests%rowtype;
begin
 if not public.has_role('admin'::public.app_role) then raise exception using errcode='42501',message='Administrator role required.'; end if;
 select * into v_row from public.refund_requests where id=p_refund_request_id for update;
 if not found or v_row.status<>'approved' then raise exception using errcode='22023',message='An approved refund request is required.'; end if;
 update public.refund_requests set status='simulated',decision_note=coalesce(nullif(pg_catalog.btrim(p_note),''),decision_note)
  where id=p_refund_request_id returning * into v_row;
 update public.simulated_payments set status='refund_simulated' where id=v_row.simulated_payment_id and status='refund_requested';
 perform public.audit_admin_action('refund_marked_simulated','refund_request',p_refund_request_id,'{}'::jsonb);
 return v_row;
end $$;
revoke all on function public.mark_refund_simulated(uuid,text) from public,anon,authenticated;
grant execute on function public.mark_refund_simulated(uuid,text) to authenticated;

commit;
