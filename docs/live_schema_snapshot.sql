-- ON THE ROAD — live schema inventory queries
-- Project: chwbyhqcmxedhfezdmfi (production)
-- Snapshot date: 2026-11-01
--
-- READ ONLY. Run each SELECT block separately in the Supabase SQL Editor.
-- This captures schema metadata and definitions; it does not export table data,
-- Auth users, Storage objects, secrets, grants/default privileges, or managed
-- Supabase internals. It is NOT a restore script and must not be run on the
-- test project as DDL. Use a verified pg_dump/custom-format backup for restore.

-- 1. Extensions and enum values
select e.extname, n.nspname as installed_schema, e.extversion
from pg_catalog.pg_extension e
join pg_catalog.pg_namespace n on n.oid = e.extnamespace
order by e.extname;

select n.nspname as schema_name, t.typname as enum_name,
       array_agg(e.enumlabel order by e.enumsortorder) as values
from pg_catalog.pg_type t
join pg_catalog.pg_enum e on e.enumtypid = t.oid
join pg_catalog.pg_namespace n on n.oid = t.typnamespace
where n.nspname in ('public', 'private')
group by n.nspname, t.typname
order by n.nspname, t.typname;

-- 2. Tables and columns (types, defaults, nullability, identity/generated)
select c.table_schema, c.table_name, c.ordinal_position, c.column_name,
       c.data_type, c.udt_schema, c.udt_name, c.is_nullable,
       c.column_default, c.is_identity, c.identity_generation,
       c.is_generated, c.generation_expression
from information_schema.columns c
where c.table_schema in ('public', 'private')
order by c.table_schema, c.table_name, c.ordinal_position;

-- 3. Constraints and indexes
select n.nspname as schema_name, c.relname as table_name, con.conname,
       con.contype, con.convalidated, pg_catalog.pg_get_constraintdef(con.oid, true) as definition
from pg_catalog.pg_constraint con
join pg_catalog.pg_class c on c.oid = con.conrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('public', 'private')
order by n.nspname, c.relname, con.conname;

select schemaname, tablename, indexname, indexdef
from pg_catalog.pg_indexes
where schemaname in ('public', 'private')
order by schemaname, tablename, indexname;

-- 4. RLS status and policies
select n.nspname as schema_name, c.relname as table_name,
       c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('public', 'private') and c.relkind in ('r', 'p')
order by n.nspname, c.relname;

select schemaname, tablename, policyname, permissive, roles, cmd,
       qual as using_expression, with_check as check_expression
from pg_catalog.pg_policies
where schemaname in ('public', 'private', 'storage')
order by schemaname, tablename, policyname;

-- 5. Views, routines, triggers
select schemaname, viewname, definition
from pg_catalog.pg_views
where schemaname in ('public', 'private')
order by schemaname, viewname;

select n.nspname as schema_name, p.proname as routine_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) as arguments,
       p.prokind, p.prosecdef as security_definer, p.proconfig,
       pg_catalog.pg_get_functiondef(p.oid) as definition
from pg_catalog.pg_proc p
join pg_catalog.pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public', 'private')
  and not exists (
    select 1 from pg_catalog.pg_depend d
    where d.classid = 'pg_catalog.pg_proc'::regclass
      and d.objid = p.oid and d.deptype = 'e'
  )
order by n.nspname, p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid);

select n.nspname as schema_name, c.relname as table_name,
       t.tgname as trigger_name, pg_catalog.pg_get_triggerdef(t.oid, true) as definition
from pg_catalog.pg_trigger t
join pg_catalog.pg_class c on c.oid = t.tgrelid
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname in ('public', 'private') and not t.tgisinternal
order by n.nspname, c.relname, t.tgname;

-- 6. Applied Supabase migration history
select version, name
from supabase_migrations.schema_migrations
order by version;
