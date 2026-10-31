-- Final hardening: cover remaining foreign keys, explicit deny policies for private worker tables,
-- and a typed organization state.
begin;
do $$ begin create type public.organization_status as enum ('active','suspended','closed'); exception when duplicate_object then null; end $$;
alter table public.organizations drop constraint if exists organizations_status_check;
alter table public.organizations alter column status drop default;
alter table public.organizations alter column status type public.organization_status using status::public.organization_status;
alter table public.organizations alter column status set default 'active'::public.organization_status;

alter table public.support_tickets add column if not exists resolved_at timestamptz;
create index if not exists support_tickets_resolved_at_idx on public.support_tickets(resolved_at) where resolved_at is not null;
create or replace function public.resolve_support_ticket(p_ticket_id uuid,p_note text default null)
returns public.support_tickets language plpgsql security definer set search_path=''
as $$
declare v_user uuid:=auth.uid(); v_row public.support_tickets%rowtype;
begin
 if v_user is null or not (public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role)) then raise exception using errcode='42501',message='Support staff role required.'; end if;
 update public.support_tickets set status='resolved',assigned_to=coalesce(assigned_to,v_user),resolved_at=pg_catalog.now(),closed_at=null
 where id=p_ticket_id and status in ('open','in_progress') returning * into v_row;
 if not found then raise exception using errcode='P0002',message='Open support ticket not found.'; end if;
 if public.has_role('admin'::public.app_role) then perform public.audit_admin_action('support_ticket_resolved','support_ticket',p_ticket_id,jsonb_build_object('note',nullif(pg_catalog.btrim(p_note),''))); end if;
 return v_row;
end $$;
revoke all on function public.resolve_support_ticket(uuid,text) from public,anon,authenticated;
grant execute on function public.resolve_support_ticket(uuid,text) to authenticated;

create index if not exists boarding_events_recorded_by_idx on public.boarding_events(recorded_by);
create index if not exists conversations_driver_id_idx on public.conversations(driver_id);
create index if not exists conversations_rider_id_idx on public.conversations(rider_id);
create index if not exists conversations_trip_id_idx on public.conversations(trip_id);
create index if not exists emergency_incidents_booking_idx on public.emergency_incidents(booking_id);
create index if not exists organizations_created_by_idx on public.organizations(created_by);
create index if not exists ratings_reviewer_idx on public.ratings(reviewer_id);
create index if not exists refund_requests_decided_by_idx on public.refund_requests(decided_by);
create index if not exists report_evidence_uploaded_by_idx on public.report_evidence(uploaded_by);
create index if not exists reports_booking_idx on public.reports(booking_id);
create index if not exists reports_resolved_by_idx on public.reports(resolved_by);
create index if not exists simulated_payments_cash_reported_by_idx on public.simulated_payments(cash_reported_by);
create index if not exists trip_shares_booking_idx on public.trip_shares(booking_id);

create policy account_deletion_jobs_deny_clients on public.account_deletion_jobs for all to authenticated using(false) with check(false);
create policy storage_deletion_jobs_deny_clients on public.storage_deletion_jobs for all to authenticated using(false) with check(false);
create policy notification_outbox_deny_clients on public.notification_outbox for all to authenticated using(false) with check(false);
create policy trip_location_updates_deny_clients on public.trip_location_updates for all to authenticated using(false) with check(false);
create policy trip_shares_deny_clients on public.trip_shares for all to authenticated using(false) with check(false);
commit;
