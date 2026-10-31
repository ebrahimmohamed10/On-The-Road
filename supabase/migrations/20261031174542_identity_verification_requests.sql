create table public.verification_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_role text not null check (user_role in ('passenger', 'driver')),
  national_id text not null check (national_id ~ '^[0-9]{14}$'),
  date_of_birth date not null,
  id_front_path text not null,
  id_back_path text not null,
  selfie_path text not null,
  license_front_path text,
  license_back_path text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'resubmission_required')),
  reviewer_notes text,
  submitted_at timestamptz not null default now(),
  constraint driver_requires_license check (
    (user_role = 'passenger' and license_front_path is null and license_back_path is null)
    or
    (user_role = 'driver' and license_front_path is not null and license_back_path is not null)
  )
);

alter table public.verification_requests enable row level security;
revoke all on table public.verification_requests from public, anon, authenticated;
grant select (id, user_id, user_role, status, submitted_at) on public.verification_requests to authenticated;
grant insert (user_id, user_role, national_id, date_of_birth, id_front_path, id_back_path, selfie_path, license_front_path, license_back_path)
  on public.verification_requests to authenticated;

create policy "Users read own verification request"
on public.verification_requests for select to authenticated
using (user_id = (select auth.uid()));

create policy "Users submit own verification request"
on public.verification_requests for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid())
      and p.role = user_role
  )
  and status = 'pending'
  and reviewer_notes is null
);
