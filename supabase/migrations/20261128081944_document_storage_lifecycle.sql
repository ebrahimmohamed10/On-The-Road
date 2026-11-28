-- Keep approved files live during review, carry forward untouched pending documents,
-- replace only the prior pending file of the same type, and delete retired objects
-- through Supabase Storage from the signed-in client after the DB commit.

alter table public.verification_documents
  add column if not exists superseded_at timestamptz,
  add column if not exists storage_deleted_at timestamptz;
alter table public.vehicle_documents
  add column if not exists superseded_at timestamptz,
  add column if not exists storage_deleted_at timestamptz;

grant select (superseded_at, storage_deleted_at)
  on public.verification_documents to authenticated;
grant update (storage_deleted_at)
  on public.verification_documents to authenticated;
grant update (storage_deleted_at)
  on public.vehicle_documents to authenticated;

drop policy if exists verification_documents_owner_mark_cleanup
  on public.verification_documents;
create policy verification_documents_owner_mark_cleanup
  on public.verification_documents for update to authenticated
  using (user_id = (select auth.uid()) and superseded_at is not null)
  with check (user_id = (select auth.uid()) and superseded_at is not null);

drop policy if exists vehicle_documents_owner_mark_cleanup
  on public.vehicle_documents;
create policy vehicle_documents_owner_mark_cleanup
  on public.vehicle_documents for update to authenticated
  using (user_id = (select auth.uid()) and superseded_at is not null)
  with check (user_id = (select auth.uid()) and superseded_at is not null);

drop policy if exists vehicle_docs_owner_delete on storage.objects;
create policy vehicle_docs_owner_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'vehicle-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create or replace function private.capture_verification_document(
  p_user_id uuid,
  p_request_id uuid,
  p_document_type public.verification_document_type,
  p_storage_path text
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_pending_id uuid;
  v_version integer;
begin
  if p_storage_path is null then
    return;
  end if;

  if exists (
    select 1 from public.verification_documents d
    where d.user_id = p_user_id
      and d.document_type = p_document_type
      and d.storage_path = p_storage_path
      and d.status = 'accepted'
      and d.superseded_at is null
  ) then
    return;
  end if;

  select d.id into v_pending_id
  from public.verification_documents d
  where d.user_id = p_user_id
    and d.document_type = p_document_type
    and d.storage_path = p_storage_path
    and d.status = 'submitted'
    and d.superseded_at is null
  order by d.uploaded_at desc
  limit 1
  for update;

  if v_pending_id is not null then
    update public.verification_documents d
    set superseded_at = pg_catalog.now(),
        updated_at = pg_catalog.now()
    where d.user_id = p_user_id
      and d.document_type = p_document_type
      and d.id <> v_pending_id
      and d.superseded_at is null
      and d.status in ('submitted', 'rejected', 'needs_resubmission');

    update public.verification_documents
    set verification_request_id = p_request_id,
        updated_at = pg_catalog.now()
    where id = v_pending_id;
    return;
  end if;

  update public.verification_documents d
  set superseded_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
  where d.user_id = p_user_id
    and d.document_type = p_document_type
    and d.storage_path is distinct from p_storage_path
    and d.superseded_at is null
    and d.status in ('submitted', 'rejected', 'needs_resubmission');

  select coalesce(max(d.version), 0) + 1 into v_version
  from public.verification_documents d
  where d.user_id = p_user_id
    and d.document_type = p_document_type;

  insert into public.verification_documents (
    user_id, verification_request_id, document_type, storage_path, version
  ) values (
    p_user_id, p_request_id, p_document_type, p_storage_path, v_version
  );
end;
$function$;

revoke all on function private.capture_verification_document(
  uuid, uuid, public.verification_document_type, text
) from public, anon, authenticated;

create or replace function private.capture_verification_documents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or auth.uid() is distinct from new.user_id then
    raise exception using errcode = '42501',
      message = 'Cannot submit another user verification request.';
  end if;

  if new.user_role = 'driver' and (
    new.vehicle_front_path is null
    or new.vehicle_right_path is null
    or new.vehicle_left_path is null
    or new.vehicle_rear_path is null
  ) then
    raise exception using errcode = '22023',
      message = 'All four vehicle exterior photos are required for driver verification.';
  end if;
  if new.user_role = 'passenger' and (
    new.vehicle_front_path is not null
    or new.vehicle_right_path is not null
    or new.vehicle_left_path is not null
    or new.vehicle_rear_path is not null
  ) then
    raise exception using errcode = '22023',
      message = 'Vehicle exterior photos are only accepted for driver verification.';
  end if;

  if not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'identity-documents'
      and o.name = new.id_front_path
      and (storage.foldername(o.name))[1] = new.user_id::text
  ) or not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'identity-documents'
      and o.name = new.id_back_path
      and (storage.foldername(o.name))[1] = new.user_id::text
  ) or not exists (
    select 1 from storage.objects o
    where o.bucket_id = 'identity-documents'
      and o.name = new.selfie_path
      and (storage.foldername(o.name))[1] = new.user_id::text
  ) then
    raise exception using errcode = '22023',
      message = 'Identity images must be uploaded to the caller’s private document folder before submission.';
  end if;

  if (new.face_front_path is null) <> (new.face_right_path is null)
     or (new.face_front_path is null) <> (new.face_left_path is null) then
    raise exception using errcode = '22023',
      message = 'All three face angle photos are required.';
  end if;
  if new.face_front_path is not null and (
    new.face_front_path is distinct from new.selfie_path
    or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.face_front_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.face_right_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.face_left_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    )
  ) then
    raise exception using errcode = '22023',
      message = 'All three face images must be uploaded to the caller’s private document folder before submission.';
  end if;

  if new.user_role = 'driver' and (
    not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.license_front_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.license_back_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.vehicle_front_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.vehicle_right_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.vehicle_left_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'identity-documents'
        and o.name = new.vehicle_rear_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    )
  ) then
    raise exception using errcode = '22023',
      message = 'Driving-license and all vehicle exterior images must be uploaded before driver verification is submitted.';
  end if;

  perform private.capture_verification_document(new.user_id,new.id,'national_id_front',new.id_front_path);
  perform private.capture_verification_document(new.user_id,new.id,'national_id_back',new.id_back_path);
  if new.face_front_path is null then
    perform private.capture_verification_document(new.user_id,new.id,'face_scan',new.selfie_path);
  else
    perform private.capture_verification_document(new.user_id,new.id,'face_scan_front',new.face_front_path);
    perform private.capture_verification_document(new.user_id,new.id,'face_scan_right',new.face_right_path);
    perform private.capture_verification_document(new.user_id,new.id,'face_scan_left',new.face_left_path);
  end if;

  if new.user_role = 'driver' then
    perform private.capture_verification_document(new.user_id,new.id,'driver_license_front',new.license_front_path);
    perform private.capture_verification_document(new.user_id,new.id,'driver_license_back',new.license_back_path);
    perform private.capture_verification_document(new.user_id,new.id,'vehicle_exterior_front',new.vehicle_front_path);
    perform private.capture_verification_document(new.user_id,new.id,'vehicle_exterior_right',new.vehicle_right_path);
    perform private.capture_verification_document(new.user_id,new.id,'vehicle_exterior_left',new.vehicle_left_path);
    perform private.capture_verification_document(new.user_id,new.id,'vehicle_exterior_rear',new.vehicle_rear_path);
  end if;

  update public.verification_requests vr_old
  set status = 'needs_resubmission'
  where vr_old.user_id = new.user_id
    and vr_old.id <> new.id
    and vr_old.status in ('submitted', 'in_review')
    and not exists (
      select 1 from public.verification_documents d
      where d.verification_request_id = vr_old.id
        and d.status = 'submitted'
        and d.superseded_at is null
    );

  update public.profiles
  set verification_status = case
    when verification_status = 'approved' then verification_status
    else 'pending'
  end
  where id = new.user_id;

  if new.user_role = 'driver' then
    insert into public.driver_profiles as existing (
      user_id, verification_request_id, status, approved_at, approved_by
    ) values (
      new.user_id, new.id, 'submitted', null, null
    ) on conflict (user_id) do update
      set verification_request_id = case
            when existing.status = 'approved' then existing.verification_request_id
            else excluded.verification_request_id
          end,
          status = case
            when existing.status = 'approved' then existing.status
            else 'submitted'::public.driver_profile_status
          end,
          approved_at = case
            when existing.status = 'approved' then existing.approved_at
            else null
          end,
          approved_by = case
            when existing.status = 'approved' then existing.approved_by
            else null
          end;
  end if;

  return null;
end;
$function$;

revoke all on function private.capture_verification_documents()
  from public, anon, authenticated;
drop trigger if exists zz_capture_vehicle_rear_photo on public.verification_requests;

create or replace function public.review_verification_request(
  p_request_id uuid,
  p_decision public.verification_decision,
  p_notes text default null
)
returns public.verification_status
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v public.verification_requests%rowtype;
  v_to public.verification_status;
  v_profile_was_approved boolean := false;
  v_driver_was_approved boolean := false;
begin
  if auth.uid() is null then
    raise exception using errcode='42501', message='Authentication required.';
  end if;
  if not exists (
    select 1 from public.user_roles ur
    where ur.user_id=auth.uid() and ur.role in ('admin','reviewer')
  ) then
    raise exception using errcode='42501', message='Reviewer or administrator role required.';
  end if;
  select * into v from public.verification_requests
  where id=p_request_id for update;
  if not found then
    raise exception using errcode='P0002', message='Request not found.';
  end if;
  if not exists (
    select 1 from public.user_roles
    where user_id=auth.uid() and role='admin'
  ) and not exists (
    select 1 from public.reviewer_assignments
    where reviewer_id=auth.uid() and verification_request_id=p_request_id
  ) then
    raise exception using errcode='42501', message='Request is not assigned to this reviewer.';
  end if;
  if not exists (
    select 1 from public.verification_documents d
    where d.verification_request_id=p_request_id
      and d.status='submitted'
      and d.superseded_at is null
  ) then
    raise exception using errcode='22023', message='Request has no active documents to review.';
  end if;

  v_to := p_decision::text::public.verification_status;
  if not exists (
    select 1 from public.allowed_status_transitions
    where entity_type='verification'
      and from_status=v.status::text
      and to_status=v_to::text
  ) then
    raise exception using errcode='22023', message='Invalid verification transition.';
  end if;

  select coalesce(p.verification_status='approved',false)
    into v_profile_was_approved
  from public.profiles p where p.id=v.user_id;
  if v.user_role='driver' then
    select exists (
      select 1 from public.driver_profiles dp
      where dp.user_id=v.user_id and dp.status='approved'
    ) into v_driver_was_approved;
  end if;

  if p_decision='approved' then
    update public.verification_documents prior_doc
    set superseded_at=pg_catalog.now(), updated_at=pg_catalog.now()
    where prior_doc.user_id=v.user_id
      and prior_doc.status='accepted'
      and prior_doc.superseded_at is null
      and exists (
        select 1 from public.verification_documents replacement
        where replacement.verification_request_id=p_request_id
          and replacement.status='submitted'
          and replacement.superseded_at is null
          and replacement.document_type=prior_doc.document_type
          and replacement.storage_path is distinct from prior_doc.storage_path
      );
  end if;

  update public.verification_requests
  set status=v_to, reviewer_notes=p_notes
  where id=p_request_id;
  update public.verification_documents
  set status=case p_decision
        when 'approved' then 'accepted'::public.document_review_status
        when 'rejected' then 'rejected'::public.document_review_status
        else 'needs_resubmission'::public.document_review_status
      end,
      updated_at=pg_catalog.now()
  where verification_request_id=p_request_id
    and status='submitted'
    and superseded_at is null;

  if p_decision in ('rejected', 'needs_resubmission') then
    update public.verification_documents
    set superseded_at=pg_catalog.now(), updated_at=pg_catalog.now()
    where verification_request_id=p_request_id
      and status in ('rejected', 'needs_resubmission')
      and superseded_at is null;
  end if;

  insert into public.verification_reviews(
    reviewer_id, verification_request_id, decision, reviewer_notes
  ) values (auth.uid(),p_request_id,p_decision,p_notes);

  if v.user_role='driver' and (p_decision='approved' or not v_driver_was_approved) then
    insert into public.driver_profiles(
      user_id,verification_request_id,status,approved_at,approved_by
    ) values (
      v.user_id,p_request_id,
      case p_decision
        when 'approved' then 'approved'::public.driver_profile_status
        when 'rejected' then 'rejected'::public.driver_profile_status
        else 'needs_resubmission'::public.driver_profile_status
      end,
      case when p_decision='approved' then pg_catalog.now() else null end,
      case when p_decision='approved' then auth.uid() else null end
    ) on conflict (user_id) do update
      set verification_request_id=excluded.verification_request_id,
          status=excluded.status,
          approved_at=excluded.approved_at,
          approved_by=excluded.approved_by;
  end if;

  update public.profiles
  set verification_status=case
        when p_decision='approved' then 'approved'
        when v_profile_was_approved then verification_status
        when p_decision='rejected' then 'rejected'
        else 'resubmission_required'
      end,
      role=case
        when v.user_role='driver' and p_decision='approved' then 'driver'
        else role
      end
  where id=v.user_id;

  if v.user_role='driver' and p_decision='approved' then
    insert into public.user_roles(user_id,role,assigned_by)
    values(v.user_id,'driver'::public.app_role,auth.uid())
    on conflict(user_id,role) do nothing;
  elsif v.user_role='driver' and p_decision='rejected' and not v_driver_was_approved then
    delete from public.user_roles
    where user_id=v.user_id and role='driver';
  end if;

  insert into public.audit_log(actor_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'verification_decided','verification_request',p_request_id,
    jsonb_build_object('decision',p_decision::text,'user_role',v.user_role,
      'preserved_previous_approval',
      (v_profile_was_approved or v_driver_was_approved) and p_decision<>'approved'));
  return v_to;
end;
$function$;

revoke all on function public.review_verification_request(
  uuid, public.verification_decision, text
) from public, anon, authenticated;
grant execute on function public.review_verification_request(
  uuid, public.verification_decision, text
) to authenticated;
