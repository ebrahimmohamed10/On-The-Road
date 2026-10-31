-- Phase 7, steps 18-20 follow-up: route support writes through the RPC,
-- keep ticket state transitions consistent, and prevent assigning closed reports.

-- A ticket must be created with its first public message by create_support_ticket().
revoke insert on public.support_tickets from authenticated;

create or replace function public.assign_report_reviewer(p_report_id uuid, p_reviewer_id uuid)
returns public.report_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.report_assignments%rowtype;
  v_status public.report_status;
begin
  if not public.has_role('admin'::public.app_role) then
    raise exception using errcode = '42501', message = 'Administrator role required.';
  end if;
  if not exists (
    select 1 from public.user_roles
    where user_id = p_reviewer_id and role = 'reviewer'::public.app_role
  ) then
    raise exception using errcode = '22023', message = 'Selected account is not a reviewer.';
  end if;

  select status into v_status
  from public.reports
  where id = p_report_id
  for update;
  if not found or v_status not in ('open', 'under_review') then
    raise exception using errcode = '22023', message = 'Only an open or under-review report can be assigned.';
  end if;

  insert into public.report_assignments(report_id, reviewer_id, assigned_by)
  values (p_report_id, p_reviewer_id, auth.uid())
  on conflict (report_id, reviewer_id)
  do update set assigned_by = excluded.assigned_by, assigned_at = pg_catalog.now()
  returning * into v_row;

  update public.reports set status = 'under_review'
  where id = p_report_id and status = 'open';

  perform public.audit_admin_action(
    'report_reviewer_assigned', 'report', p_report_id,
    pg_catalog.jsonb_build_object('reviewer_id', p_reviewer_id)
  );
  return v_row;
end;
$$;
revoke all on function public.assign_report_reviewer(uuid, uuid) from public, anon, authenticated;
grant execute on function public.assign_report_reviewer(uuid, uuid) to authenticated;

create or replace function public.add_support_message(p_ticket_id uuid, p_body text, p_is_internal boolean default false)
returns public.support_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_ticket public.support_tickets%rowtype;
  v_message public.support_messages%rowtype;
  v_staff boolean;
begin
  if v_user is null or p_body is null or length(pg_catalog.btrim(p_body)) not between 1 and 5000 then
    raise exception using errcode = '22023', message = 'Sign in and provide a valid message.';
  end if;
  v_staff := public.has_role('admin'::public.app_role) or public.has_role('reviewer'::public.app_role);

  select * into v_ticket from public.support_tickets where id = p_ticket_id for update;
  if not found or (v_ticket.user_id <> v_user and not v_staff) then
    raise exception using errcode = '42501', message = 'Ticket not found or not accessible.';
  end if;
  if p_is_internal and not v_staff then
    raise exception using errcode = '42501', message = 'Only support staff can create internal notes.';
  end if;
  if v_ticket.status = 'closed' then
    raise exception using errcode = '22023', message = 'This ticket is closed.';
  end if;
  if v_ticket.status = 'resolved' and not v_staff then
    raise exception using errcode = '22023', message = 'This ticket is resolved.';
  end if;

  insert into public.support_messages(ticket_id, sender_id, body, is_internal)
  values (p_ticket_id, v_user, pg_catalog.btrim(p_body), p_is_internal)
  returning * into v_message;

  if v_staff and v_ticket.status in ('open', 'resolved') then
    update public.support_tickets
    set status = 'in_progress',
        assigned_to = coalesce(assigned_to, v_user),
        resolved_at = null,
        closed_at = null
    where id = p_ticket_id;
  end if;
  return v_message;
end;
$$;
revoke all on function public.add_support_message(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.add_support_message(uuid, text, boolean) to authenticated;

create or replace function public.close_own_support_ticket(p_ticket_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.support_tickets
  set status = 'closed', closed_at = pg_catalog.now()
  where id = p_ticket_id
    and user_id = auth.uid()
    and status in ('open', 'in_progress', 'resolved');
  return found;
end;
$$;
revoke all on function public.close_own_support_ticket(uuid) from public, anon, authenticated;
grant execute on function public.close_own_support_ticket(uuid) to authenticated;

