do $migration$
begin
  if exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.profiles'::regclass
      and c.confrelid = 'auth.users'::regclass
      and c.contype = 'f'
      and c.confdeltype <> 'c'
  ) then
    raise exception 'public.profiles already has a non-cascading auth.users foreign key; review it before applying this migration.';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_constraint c
    where c.conrelid = 'public.profiles'::regclass
      and c.confrelid = 'auth.users'::regclass
      and c.contype = 'f'
      and c.confdeltype = 'c'
  ) then
    -- NOT VALID allows the existing orphaned profile rows to be reviewed and
    -- cleaned separately, while new rows are checked and Auth deletions cascade.
    alter table public.profiles
      add constraint profiles_id_auth_users_fkey
      foreign key (id) references auth.users(id)
      on delete cascade
      not valid;
  end if;
end;
$migration$;
