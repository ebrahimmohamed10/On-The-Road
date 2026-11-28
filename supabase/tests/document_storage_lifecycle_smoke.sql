begin;
do $test$
declare
  u uuid := '3f9d6d6e-fac9-4576-8b98-1872005b8051';
  admin_id uuid := 'b0c99e1e-716a-4bf4-b1af-0ad10b0bd5c9';
  req1 uuid; req2 uuid; req3 uuid; req4 uuid;
begin
  insert into auth.users(id,instance_id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
  (u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','+201099900101',now(),'{}','{"name":"Lifecycle Test","role":"passenger"}',now(),now()),
  (admin_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','+201099900102',now(),'{}','{"name":"Lifecycle Admin","role":"passenger"}',now(),now());
  insert into public.user_roles(user_id,role) values(admin_id,'admin'::public.app_role) on conflict(user_id,role) do nothing;
  update public.profiles set verification_status='approved' where id=u;
  insert into storage.objects(bucket_id,name,owner,metadata)
  select 'identity-documents',u::text||'/'||x,u,'{}'::jsonb
  from unnest(array['id-front-approved.jpg','id-back-approved.jpg','face-front-approved.jpg','face-right-approved.jpg','face-left-approved.jpg','id-front-pending-1.jpg','id-front-pending-2.jpg','id-front-pending-3.jpg','id-back-pending-1.jpg']) x;

  perform pg_catalog.set_config('request.jwt.claim.sub',u::text,true);
  insert into public.verification_requests(user_id,user_role,national_id,date_of_birth,gender,city,id_front_path,id_back_path,selfie_path,face_front_path,face_right_path,face_left_path)
  values(u,'passenger','00000000000000','2000-01-01','male','Test City',u||'/id-front-approved.jpg',u||'/id-back-approved.jpg',u||'/face-front-approved.jpg',u||'/face-front-approved.jpg',u||'/face-right-approved.jpg',u||'/face-left-approved.jpg')
  returning id into req1;
  update public.verification_documents set status='accepted' where verification_request_id=req1;
  update public.verification_requests set status='approved' where id=req1;

  insert into public.verification_requests(user_id,user_role,national_id,date_of_birth,gender,city,id_front_path,id_back_path,selfie_path,face_front_path,face_right_path,face_left_path)
  values(u,'passenger','00000000000000','2000-01-01','male','Test City',u||'/id-front-pending-1.jpg',u||'/id-back-approved.jpg',u||'/face-front-approved.jpg',u||'/face-front-approved.jpg',u||'/face-right-approved.jpg',u||'/face-left-approved.jpg')
  returning id into req2;
  if not exists(select 1 from public.verification_documents where user_id=u and document_type='national_id_front' and storage_path=u||'/id-front-approved.jpg' and status='accepted' and superseded_at is null)
    or not exists(select 1 from public.verification_documents where verification_request_id=req2 and document_type='national_id_front' and storage_path=u||'/id-front-pending-1.jpg' and status='submitted' and superseded_at is null)
    or exists(select 1 from public.verification_documents where verification_request_id=req2 and document_type='national_id_back') then
    raise exception 'First replacement did not preserve approved file or avoid duplicating unchanged documents';
  end if;

  insert into public.verification_requests(user_id,user_role,national_id,date_of_birth,gender,city,id_front_path,id_back_path,selfie_path,face_front_path,face_right_path,face_left_path)
  values(u,'passenger','00000000000000','2000-01-01','male','Test City',u||'/id-front-pending-2.jpg',u||'/id-back-approved.jpg',u||'/face-front-approved.jpg',u||'/face-front-approved.jpg',u||'/face-right-approved.jpg',u||'/face-left-approved.jpg')
  returning id into req3;
  if not exists(select 1 from public.verification_documents where storage_path=u||'/id-front-pending-1.jpg' and superseded_at is not null)
    or not exists(select 1 from public.verification_documents where storage_path=u||'/id-front-pending-2.jpg' and status='submitted' and superseded_at is null)
    or not exists(select 1 from public.verification_documents where storage_path=u||'/id-front-approved.jpg' and status='accepted' and superseded_at is null) then
    raise exception 'Same-document replacement did not supersede only the older pending file';
  end if;

  insert into public.verification_requests(user_id,user_role,national_id,date_of_birth,gender,city,id_front_path,id_back_path,selfie_path,face_front_path,face_right_path,face_left_path)
  values(u,'passenger','00000000000000','2000-01-01','male','Test City',u||'/id-front-pending-2.jpg',u||'/id-back-pending-1.jpg',u||'/face-front-approved.jpg',u||'/face-front-approved.jpg',u||'/face-right-approved.jpg',u||'/face-left-approved.jpg')
  returning id into req4;
  if not exists(select 1 from public.verification_documents where storage_path=u||'/id-front-pending-2.jpg' and verification_request_id=req4 and status='submitted' and superseded_at is null)
    or not exists(select 1 from public.verification_documents where storage_path=u||'/id-back-pending-1.jpg' and verification_request_id=req4 and status='submitted' and superseded_at is null) then
    raise exception 'Unchanged pending image was not carried forward with a different document change';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.review_verification_request(req4,'rejected','lifecycle test');
  if not exists(select 1 from public.verification_documents where storage_path=u||'/id-front-approved.jpg' and status='accepted' and superseded_at is null)
    or not exists(select 1 from public.verification_documents where storage_path=u||'/id-front-pending-2.jpg' and status='rejected' and superseded_at is not null)
    or not exists(select 1 from public.profiles where id=u and verification_status='approved') then
    raise exception 'Rejecting a replacement did not preserve the previously accepted file/state';
  end if;

  perform pg_catalog.set_config('request.jwt.claim.sub',u::text,true);
  insert into public.verification_requests(user_id,user_role,national_id,date_of_birth,gender,city,id_front_path,id_back_path,selfie_path,face_front_path,face_right_path,face_left_path)
  values(u,'passenger','00000000000000','2000-01-01','male','Test City',u||'/id-front-pending-3.jpg',u||'/id-back-approved.jpg',u||'/face-front-approved.jpg',u||'/face-front-approved.jpg',u||'/face-right-approved.jpg',u||'/face-left-approved.jpg')
  returning id into req3;
  perform pg_catalog.set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.review_verification_request(req3,'approved','lifecycle test');
  if not exists(select 1 from public.verification_documents where storage_path=u||'/id-front-pending-3.jpg' and status='accepted' and superseded_at is null)
    or not exists(select 1 from public.verification_documents where storage_path=u||'/id-front-approved.jpg' and status='accepted' and superseded_at is not null)
    or not exists(select 1 from public.profiles where id=u and verification_status='approved') then
    raise exception 'Approving a replacement did not activate it and retire the previous accepted file';
  end if;
end;
$test$;
rollback;
