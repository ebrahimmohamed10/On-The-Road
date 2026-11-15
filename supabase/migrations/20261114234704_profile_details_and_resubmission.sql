-- Persist gender and city with the verified identity data while retaining the
-- existing private-details boundary for national ID and date of birth.
alter table public.user_private_details
  add column if not exists gender text;

alter table public.verification_requests
  add column if not exists gender text,
  add column if not exists city text;

alter table public.user_private_details
  add constraint user_private_details_gender_check
  check (gender is null or gender in ('male', 'female')) not valid;

alter table public.verification_requests
  add constraint verification_requests_gender_check
  check (gender is null or gender in ('male', 'female')) not valid;

grant insert (gender), update (gender)
  on public.user_private_details to authenticated;
grant insert (gender, city)
  on public.verification_requests to authenticated;

create or replace function public.capture_private_verification_fields()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if auth.uid() is null or new.user_id is distinct from auth.uid() then
    raise exception using errcode = '42501', message = 'Cannot submit another user verification data.';
  end if;

  insert into public.user_private_details as existing (
    user_id, full_legal_name, national_id, date_of_birth, city, gender
  )
  values (
    new.user_id,
    (select p.name from public.profiles p where p.id = new.user_id),
    new.national_id,
    new.date_of_birth,
    new.city,
    new.gender
  )
  on conflict (user_id) do update
    set full_legal_name = coalesce(excluded.full_legal_name, existing.full_legal_name),
        national_id = excluded.national_id,
        date_of_birth = excluded.date_of_birth,
        city = coalesce(excluded.city, existing.city),
        gender = coalesce(excluded.gender, existing.gender);

  -- Identity number and date of birth stay out of the reviewer-facing request.
  new.national_id := null;
  new.date_of_birth := null;
  return new;
end;
$function$;

revoke all on function public.capture_private_verification_fields()
  from public, anon, authenticated;

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

  if (new.face_front_path is null) <> (new.face_right_path is null)
     or (new.face_front_path is null) <> (new.face_left_path is null) then
    raise exception using errcode = '22023', message = 'All three face angle photos are required.';
  end if;
  if new.face_front_path is not null and (
    new.face_front_path is distinct from new.selfie_path
    or not exists (
      select 1 from storage.objects o where o.bucket_id = 'identity-documents'
        and o.name = new.face_front_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o where o.bucket_id = 'identity-documents'
        and o.name = new.face_right_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o where o.bucket_id = 'identity-documents'
        and o.name = new.face_left_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    )
  ) then
    raise exception using errcode = '22023', message = 'All three face images must be uploaded to the caller’s private document folder before submission.';
  end if;

  if new.user_role = 'driver' and (
    not exists (
      select 1 from storage.objects o where o.bucket_id = 'identity-documents'
        and o.name = new.license_front_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o where o.bucket_id = 'identity-documents'
        and o.name = new.license_back_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o where o.bucket_id = 'identity-documents'
        and o.name = new.vehicle_front_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o where o.bucket_id = 'identity-documents'
        and o.name = new.vehicle_right_path
        and (storage.foldername(o.name))[1] = new.user_id::text
    ) or not exists (
      select 1 from storage.objects o where o.bucket_id = 'identity-documents'
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

  update public.profiles
  set verification_status = 'pending'
  where id = new.user_id;

  if new.user_role = 'driver' then
    delete from public.user_roles
    where user_id = new.user_id and role = 'driver';

    insert into public.driver_profiles as existing(user_id, verification_request_id, status, approved_at, approved_by)
    values (new.user_id, new.id, 'submitted', null, null)
    on conflict (user_id) do update
      set verification_request_id = excluded.verification_request_id,
          status = 'submitted'::public.driver_profile_status,
          approved_at = null,
          approved_by = null;
  end if;

  return null;
end;
$function$;

revoke all on function private.capture_verification_documents()
  from public, anon, authenticated;
