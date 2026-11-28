create table if not exists private.phone_signup_attempts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  attempt_id uuid not null,
  created_at timestamptz not null default pg_catalog.now()
);

revoke all on table private.phone_signup_attempts
  from public, anon, authenticated;

create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  requested_role text;
  signup_attempt_id uuid;
begin
  requested_role := case
    when new.raw_user_meta_data ->> 'role' = 'driver' then 'driver'
    else 'passenger'
  end;
  signup_attempt_id := nullif(
    new.raw_user_meta_data ->> 'signup_attempt_id',
    ''
  )::uuid;

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

  insert into public.user_roles (user_id, role)
  values (new.id, 'rider'::public.app_role)
  on conflict (user_id, role) do nothing;

  insert into public.user_private_details (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  insert into public.notification_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  if signup_attempt_id is not null then
    insert into private.phone_signup_attempts (user_id, attempt_id)
    values (new.id, signup_attempt_id)
    on conflict (user_id) do update
      set attempt_id = excluded.attempt_id,
          created_at = pg_catalog.now();
  end if;

  return new;
end;
$function$;

revoke all on function public.handle_new_auth_user_profile()
  from public, anon, authenticated;

create or replace function public.consume_phone_signup_attempt(p_attempt_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_stored_attempt_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501',
      message = 'Authentication required.';
  end if;

  delete from private.phone_signup_attempts
  where user_id = v_user_id
  returning attempt_id into v_stored_attempt_id;

  return v_stored_attempt_id is not null
    and v_stored_attempt_id = p_attempt_id;
end;
$function$;

revoke all on function public.consume_phone_signup_attempt(uuid)
  from public, anon, authenticated;
grant execute on function public.consume_phone_signup_attempt(uuid)
  to authenticated;
