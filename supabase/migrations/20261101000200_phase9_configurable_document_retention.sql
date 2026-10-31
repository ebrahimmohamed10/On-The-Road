-- Phase 9, step 22: apply the admin-managed document retention setting when
-- an account deletion is approved. Existing queued dates remain unchanged.

create or replace function public.review_account_deletion_request(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null
)
returns public.account_deletion_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row public.account_deletion_requests%rowtype;
  v_next public.account_deletion_status;
  v_retention_months integer;
begin
  if not public.has_role('admin'::public.app_role) then
    raise exception using errcode = '42501', message = 'Administrator role required.';
  end if;

  select (s.value #>> '{}')::integer
  into v_retention_months
  from public.app_settings s
  where s.key = 'identity_document_retention_months_after_closure';
  v_retention_months := coalesce(v_retention_months, 12);
  if v_retention_months < 1 or v_retention_months > 120 then
    raise exception using errcode = '22023', message = 'Identity document retention must be between 1 and 120 months.';
  end if;

  select * into v_row
  from public.account_deletion_requests
  where id = p_request_id
  for update;
  if not found or v_row.status <> 'requested' then
    raise exception using errcode = 'P0002', message = 'Pending deletion request not found.';
  end if;

  v_next := case when p_approve then 'processing'::public.account_deletion_status
                 else 'rejected'::public.account_deletion_status end;
  update public.account_deletion_requests
  set status = v_next,
      processed_at = case when p_approve then null else pg_catalog.now() end
  where id = p_request_id
  returning * into v_row;

  if p_approve then
    insert into public.account_deletion_jobs(request_id, user_id, operation)
    values (v_row.id, v_row.user_id, 'disable_auth_user');

    insert into public.storage_deletion_jobs(bucket_id, object_path, delete_after)
    select 'identity-documents', d.storage_path,
           pg_catalog.now() + pg_catalog.make_interval(months => v_retention_months)
    from public.verification_documents d
    where d.user_id = v_row.user_id
    union
    select 'vehicle-documents', d.storage_path,
           pg_catalog.now() + pg_catalog.make_interval(months => v_retention_months)
    from public.vehicle_documents d
    where d.user_id = v_row.user_id
    union
    select 'avatars', p.avatar_path, pg_catalog.now()
    from public.profiles p
    where p.id = v_row.user_id and p.avatar_path is not null
    on conflict (bucket_id, object_path) do nothing;
  end if;

  perform public.audit_admin_action(
    case when p_approve then 'account_deletion_queued' else 'account_deletion_rejected' end,
    'account_deletion_request', p_request_id,
    pg_catalog.jsonb_build_object('note', nullif(pg_catalog.btrim(p_note), ''),
                                 'document_retention_months', v_retention_months)
  );
  return v_row;
end;
$$;
revoke all on function public.review_account_deletion_request(uuid, boolean, text) from public, anon, authenticated;
grant execute on function public.review_account_deletion_request(uuid, boolean, text) to authenticated;

