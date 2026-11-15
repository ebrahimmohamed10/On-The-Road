-- Store the three still images captured during face liveness: front, right, left.
-- Keep selfie_path as the legacy frontal image field for existing clients/records.
alter type public.verification_document_type
  add value if not exists 'face_scan_front';
alter type public.verification_document_type
  add value if not exists 'face_scan_right';
alter type public.verification_document_type
  add value if not exists 'face_scan_left';

alter table public.verification_requests
  add column if not exists face_front_path text,
  add column if not exists face_right_path text,
  add column if not exists face_left_path text;

grant insert(face_front_path, face_right_path, face_left_path)
  on public.verification_requests to authenticated;

create or replace function private.capture_verification_documents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or auth.uid() is distinct from new.user_id then
    raise exception using errcode = '42501', message = 'Cannot submit another user verification request.';
  end if;

  if new.user_role = 'driver' and (
    new.vehicle_front_path is null
    or new.vehicle_right_path is null
    or new.vehicle_left_path is null
  ) then
    raise exception using errcode = '22023', message = 'All three vehicle exterior photos are required for driver verification.';
  end if;
  if new.user_role = 'passenger' and (
    new.vehicle_front_path is not null
    or new.vehicle_right_path is not null
    or new.vehicle_left_path is not null
  ) then
    raise exception using errcode = '22023', message = 'Vehicle exterior photos are only accepted for driver verification.';
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
    raise exception using errcode = '22023', message = 'Identity images must be uploaded to the caller’s private document folder before submission.';
  end if;

  -- New clients submit all three face images. Legacy clients with no angle
  -- columns continue to be stored as one face_scan document.
  if (new.face_front_path is null) <> (new.face_right_path is null)
     or (new.face_front_path is null) <> (new.face_left_path is null) then
    raise exception using errcode = '22023', message = 'All three face angle photos are required.';
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
    raise exception using errcode = '22023', message = 'All three face images must be uploaded to the caller’s private document folder before submission.';
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
    )
  ) then
    raise exception using errcode = '22023', message = 'Driving-license and vehicle exterior images must be uploaded before driver verification is submitted.';
  end if;

  insert into public.verification_documents(user_id, verification_request_id, document_type, storage_path)
  values
    (new.user_id, new.id, 'national_id_front', new.id_front_path),
    (new.user_id, new.id, 'national_id_back', new.id_back_path)
  on conflict (verification_request_id, document_type, version) do nothing;

  if new.face_front_path is null then
    insert into public.verification_documents(user_id, verification_request_id, document_type, storage_path)
    values (new.user_id, new.id, 'face_scan', new.selfie_path)
    on conflict (verification_request_id, document_type, version) do nothing;
  else
    insert into public.verification_documents(user_id, verification_request_id, document_type, storage_path)
    values
      (new.user_id, new.id, 'face_scan_front', new.face_front_path),
      (new.user_id, new.id, 'face_scan_right', new.face_right_path),
      (new.user_id, new.id, 'face_scan_left', new.face_left_path)
    on conflict (verification_request_id, document_type, version) do nothing;
  end if;

  if new.license_front_path is not null then
    insert into public.verification_documents(user_id, verification_request_id, document_type, storage_path)
    values (new.user_id, new.id, 'driver_license_front', new.license_front_path)
    on conflict (verification_request_id, document_type, version) do nothing;
  end if;
  if new.license_back_path is not null then
    insert into public.verification_documents(user_id, verification_request_id, document_type, storage_path)
    values (new.user_id, new.id, 'driver_license_back', new.license_back_path)
    on conflict (verification_request_id, document_type, version) do nothing;
  end if;
  if new.user_role = 'driver' then
    insert into public.verification_documents(user_id, verification_request_id, document_type, storage_path)
    values
      (new.user_id, new.id, 'vehicle_exterior_front', new.vehicle_front_path),
      (new.user_id, new.id, 'vehicle_exterior_right', new.vehicle_right_path),
      (new.user_id, new.id, 'vehicle_exterior_left', new.vehicle_left_path)
    on conflict (verification_request_id, document_type, version) do nothing;
  end if;

  update public.verification_requests
  set id_front_path = null,
      id_back_path = null,
      selfie_path = null,
      face_front_path = null,
      face_right_path = null,
      face_left_path = null,
      license_front_path = null,
      license_back_path = null,
      vehicle_front_path = null,
      vehicle_right_path = null,
      vehicle_left_path = null
  where id = new.id;

  if new.user_role = 'driver' then
    insert into public.driver_profiles as existing(user_id, verification_request_id, status)
    values (new.user_id, new.id, 'submitted')
    on conflict (user_id) do update
      set verification_request_id = excluded.verification_request_id,
          status = case
            when existing.status = 'approved' then existing.status
            else 'submitted'::public.driver_profile_status
          end;
  end if;

  return null;
end;
$function$;

revoke all on function private.capture_verification_documents()
  from public, anon, authenticated;
