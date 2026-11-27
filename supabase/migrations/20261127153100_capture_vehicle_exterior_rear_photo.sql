alter table public.verification_requests
  add column if not exists vehicle_rear_path text;

grant insert (vehicle_rear_path)
  on public.verification_requests to authenticated;

create or replace function private.validate_vehicle_rear_photo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or auth.uid() is distinct from new.user_id then
    raise exception using errcode = '42501',
      message = 'Cannot submit another user vehicle image.';
  end if;

  if new.user_role = 'driver' and new.vehicle_rear_path is null then
    raise exception using errcode = '22023',
      message = 'The rear vehicle photo is required for driver verification.';
  end if;
  if new.user_role = 'passenger' and new.vehicle_rear_path is not null then
    raise exception using errcode = '22023',
      message = 'Vehicle exterior photos are only accepted for driver verification.';
  end if;

  if new.vehicle_rear_path is not null and not exists (
    select 1
    from storage.objects o
    where o.bucket_id = 'identity-documents'
      and o.name = new.vehicle_rear_path
      and (storage.foldername(o.name))[1] = new.user_id::text
  ) then
    raise exception using errcode = '22023',
      message = 'The rear vehicle image must be uploaded to the caller’s private document folder.';
  end if;

  return new;
end;
$function$;

revoke all on function private.validate_vehicle_rear_photo()
  from public, anon, authenticated;

create trigger verification_requests_validate_vehicle_rear
before insert on public.verification_requests
for each row execute function private.validate_vehicle_rear_photo();

create or replace function private.capture_vehicle_rear_photo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or auth.uid() is distinct from new.user_id then
    raise exception using errcode = '42501',
      message = 'Cannot submit another user vehicle image.';
  end if;

  if new.vehicle_rear_path is not null then
    insert into public.verification_documents (
      user_id,
      verification_request_id,
      document_type,
      storage_path
    ) values (
      new.user_id,
      new.id,
      'vehicle_exterior_rear',
      new.vehicle_rear_path
    ) on conflict (verification_request_id, document_type, version) do nothing;

    update public.verification_requests
    set vehicle_rear_path = null
    where id = new.id;
  end if;

  return null;
end;
$function$;

revoke all on function private.capture_vehicle_rear_photo()
  from public, anon, authenticated;

-- Run after the existing document capture trigger. This keeps the raw object
-- path out of verification_requests, like the other identity document paths.
create trigger zz_capture_vehicle_rear_photo
after insert on public.verification_requests
for each row execute function private.capture_vehicle_rear_photo();
