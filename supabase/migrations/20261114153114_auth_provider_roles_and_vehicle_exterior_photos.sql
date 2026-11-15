-- Account role is a requested app experience, while user_roles is the
-- authorization source. Every auth provider gets the same baseline rows.
create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_role text;
begin
  requested_role := case
    when new.raw_user_meta_data ->> 'role' = 'driver' then 'driver'
    else 'passenger'
  end;

  insert into public.profiles (id, name, phone, role)
  values (
    new.id,
    coalesce(
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'name'), ''),
      nullif(pg_catalog.btrim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(new.phone, ''),
      'New user'
    ),
    new.phone,
    requested_role
  )
  on conflict (id) do nothing;

  -- Riders are the baseline capability. A requested driver stays a rider
  -- until an administrator approves the verification request.
  insert into public.user_roles (user_id, role)
  values (new.id, 'rider'::public.app_role)
  on conflict (user_id, role) do nothing;

  insert into public.user_private_details (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;
revoke all on function public.handle_new_auth_user_profile()
  from public, anon, authenticated;

-- Social providers do not carry the app's role choice in their identity
-- claims. Let an authenticated user set only their own requested app role.
create or replace function public.set_requested_account_role(p_role text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = 'Authentication required.';
  end if;
  if p_role is null or p_role not in ('passenger', 'driver') then
    raise exception using errcode = '22023', message = 'Unsupported account role.';
  end if;
  if exists (
    select 1 from public.user_roles
    where user_id = v_user_id and role in ('admin'::public.app_role, 'reviewer'::public.app_role)
  ) then
    raise exception using errcode = '42501', message = 'Privileged accounts cannot change their requested role.';
  end if;
  if p_role <> 'driver' and (
    exists (
      select 1 from public.user_roles
      where user_id = v_user_id and role = 'driver'::public.app_role
    )
    or exists (
      select 1 from public.driver_profiles
      where user_id = v_user_id and status in ('submitted', 'in_review', 'approved')
    )
  ) then
    raise exception using errcode = '22023', message = 'A submitted or approved driver account cannot be changed to passenger.';
  end if;

  update public.profiles
  set role = p_role
  where id = v_user_id;
  if not found then
    raise exception using errcode = 'P0002', message = 'Account profile not found.';
  end if;

  return p_role;
end;
$$;
revoke all on function public.set_requested_account_role(text)
  from public, anon, authenticated;
grant execute on function public.set_requested_account_role(text)
  to authenticated;

-- Keep vehicle exterior photos in the same private verification-document
-- lifecycle as the identity and license photos captured in this flow.
alter type public.verification_document_type
  add value if not exists 'vehicle_exterior_front';
alter type public.verification_document_type
  add value if not exists 'vehicle_exterior_right';
alter type public.verification_document_type
  add value if not exists 'vehicle_exterior_left';

alter table public.verification_requests
  add column if not exists vehicle_front_path text,
  add column if not exists vehicle_right_path text,
  add column if not exists vehicle_left_path text;

grant insert(vehicle_front_path, vehicle_right_path, vehicle_left_path)
  on public.verification_requests to authenticated;

create or replace function private.capture_verification_documents()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
    (new.user_id, new.id, 'national_id_back', new.id_back_path),
    (new.user_id, new.id, 'face_scan', new.selfie_path)
  on conflict (verification_request_id, document_type, version) do nothing;

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

  -- Private object paths are canonical in verification_documents, not on the
  -- broadly readable request row.
  update public.verification_requests
  set id_front_path = null,
      id_back_path = null,
      selfie_path = null,
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
$$;
revoke all on function private.capture_verification_documents()
  from public, anon, authenticated;
