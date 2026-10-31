-- Phase 2 follow-up: cover every new foreign key with an index, narrow public
-- driver profile reads, and verify uploaded objects before accepting documents.
begin;

create index if not exists audit_log_actor_id_idx on public.audit_log(actor_id);
create index if not exists driver_profiles_approved_by_idx on public.driver_profiles(approved_by);
create index if not exists driver_profiles_verification_request_idx on public.driver_profiles(verification_request_id);
create index if not exists reviewer_assignments_assigned_by_idx on public.reviewer_assignments(assigned_by);
create index if not exists vehicles_approved_by_idx on public.vehicles(approved_by);
create index if not exists verification_reviews_reviewer_idx on public.verification_reviews(reviewer_id);

revoke all on public.driver_profiles from authenticated;
grant select(id,user_id,status,approved_at,created_at,updated_at) on public.driver_profiles to authenticated;
grant insert(user_id,verification_request_id) on public.driver_profiles to authenticated;

drop policy if exists vehicle_documents_owner_insert on public.vehicle_documents;
create policy vehicle_documents_owner_insert on public.vehicle_documents
for insert to authenticated
with check (
  user_id=(select auth.uid())
  and exists(select 1 from public.vehicles v where v.id=vehicle_id and v.owner_id=(select auth.uid()) and v.status in ('draft','needs_resubmission'))
  and exists(select 1 from storage.objects o where o.bucket_id='vehicle-documents' and o.name=storage_path and (storage.foldername(o.name))[1]=(select auth.uid())::text)
);

create or replace function private.capture_verification_documents()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or auth.uid() is distinct from new.user_id then
    raise exception using errcode='42501',message='Cannot submit another user verification request.';
  end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.id_front_path and (storage.foldername(o.name))[1]=new.user_id::text)
     or not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.id_back_path and (storage.foldername(o.name))[1]=new.user_id::text)
     or not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.selfie_path and (storage.foldername(o.name))[1]=new.user_id::text) then
    raise exception using errcode='22023',message='Identity images must be uploaded to the caller’s private document folder before submission.';
  end if;
  if new.user_role='driver' and (
       not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.license_front_path and (storage.foldername(o.name))[1]=new.user_id::text)
       or not exists(select 1 from storage.objects o where o.bucket_id='identity-documents' and o.name=new.license_back_path and (storage.foldername(o.name))[1]=new.user_id::text)
  ) then
    raise exception using errcode='22023',message='Both driving-license images must be uploaded before submission.';
  end if;
  insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path) values
    (new.user_id,new.id,'national_id_front',new.id_front_path),
    (new.user_id,new.id,'national_id_back',new.id_back_path),
    (new.user_id,new.id,'face_scan',new.selfie_path)
  on conflict(verification_request_id,document_type,version) do nothing;
  if new.license_front_path is not null then
    insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path)
    values(new.user_id,new.id,'driver_license_front',new.license_front_path)
    on conflict(verification_request_id,document_type,version) do nothing;
  end if;
  if new.license_back_path is not null then
    insert into public.verification_documents(user_id,verification_request_id,document_type,storage_path)
    values(new.user_id,new.id,'driver_license_back',new.license_back_path)
    on conflict(verification_request_id,document_type,version) do nothing;
  end if;
  update public.verification_requests
  set id_front_path=null,id_back_path=null,selfie_path=null,license_front_path=null,license_back_path=null
  where id=new.id;
  if new.user_role='driver' then
    insert into public.driver_profiles(user_id,verification_request_id,status)
    values(new.user_id,new.id,'submitted')
    on conflict(user_id) do update set verification_request_id=excluded.verification_request_id;
  end if;
  return null;
end;
$$;
revoke all on function private.capture_verification_documents() from public,anon,authenticated;

commit;
