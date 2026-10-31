# ON THE ROAD — migration reconciliation

**Purpose:** record the difference between the live Supabase migration ledger and
the local `supabase/migrations` directory before anyone runs `supabase db push`.

## Production project

- Project ref: `chwbyhqcmxedhfezdmfi` (`On The Road`)
- Production branch: `main`
- Live database: PostgreSQL 17.11, region `eu-west-1`
- Live migration ledger: 28 applied entries (read from Supabase on 2026-11-01)
- Local directory: 28 SQL files

## Differences confirmed

1. The local files `202610300001_security_profiles_rls.sql` and
   `202610300002_atomic_segment_booking.sql` are not present in the live ledger.
   Their comments describe them as manual/review migrations. Do not infer that
   they are equivalent to any remote entry without comparing their SQL.
2. The live ledger contains `20261031170008_tighten_legacy_rls_and_driver_approval`
   and `20261031174208_private_identity_document_storage`; there are no local
   files with those versions/names.
3. `20261031174542_identity_verification_requests` and the phase 1–2 migration
   names/versions match between local and live.
4. The following later migrations have equivalent-looking names but different
   version numbers. They are not safe to push as-is because Supabase identifies
   migrations by version:

| Live version | Local version | Migration |
|---|---|---|
| `20261031214058` | `20261031220000` | `phase3_trip_stops_and_fares` |
| `20261031214345` | `20261031220500` | `phase3_availability_rpc_scope` |
| `20261031215127` | `20261031221000` | `phase4_booking_status_vocabulary` |
| `20261031215221` | `20261031221500` | `phase4_booking_workflows_history` |
| `20261031215645` | `20261031222000` | `phase5_pricing_snapshots` |
| `20261031215934` | `20261031222500` | `phase6_messaging_notifications_ratings_hardening` |
| `20261031220302` | `20261101000100` | `phase7_reports_support_retention_hardening` |
| `20261031220526` | `20261101000200` | `phase9_configurable_document_retention` |
| `20261031220635` | `20261101000300` | `phase9_fk_indexes` |

The live ledger also includes the migrations through `phase7b_final_hardening`
and `account_deletion_worker_schedule`; those versions match local.

## Test project status

- A separate project named `On The Road Test` was created in the same Free
  organization, region `eu-west-1`, ref `yzsjzvirbbelfxxrncey`.
- The Supabase cost quote for a new project was `$0/month`; the organization
  reports the `free` plan. Verify the Billing page in the dashboard before
  relying on this as a billing guarantee.
- The test project is currently empty. It has no schema, users, seed trip, or
  applied migrations. Do not run the production concurrency test there until a
  reviewed schema snapshot/baseline has been loaded.

## Safe reconciliation procedure

1. Keep this branch/commit as a source backup. Do not run `supabase db push`.
2. Produce a real schema-only backup of production using the Supabase CLI or
   dashboard backup/export workflow. `live_schema_snapshot.sql` in this repo is
   a read-only catalog inventory query, **not** a restorable `pg_dump` file.
3. Compare the schema-only backup with all local migration SQL and the live
   migration ledger. Record each local-only, remote-only, and version-mismatched
   change; do not map versions based on names alone.
4. Choose one documented baseline/repair plan for a clean test project. Load
   it only into `On The Road Test`, then verify its schema and RPC definitions
   against production.
5. Seed test-only identities and a future trip with exactly one available seat.
   Run two authenticated booking requests concurrently; expected result: one
   pending booking succeeds, the other receives the no-seats error, and the
   remaining-seat count is zero. Repeat after confirming cancellation/expiry
   releases the seat.
6. Only after the test schema and results are reviewed should a migration
   history repair or new migration be considered for production.

## Current relevant database facts

- `search_trips` exists in production and is executable by `authenticated`; it
  searches city stops, departure time, seat availability, and fare. The app now
  calls it. PostGIS distance search remains out of scope for the graduation MVP.
- `create_booking` locks the trip row with `FOR UPDATE`, checks occupancy for
  each route segment, and inserts a booking plus its segment allocations in the
  same transaction. The concurrent last-seat test has not yet been run.
- `price_minor` / `total_price_minor` are integer minor-unit columns. The app
  reads `total_price_minor` for display calculations. Production still has a
  separate `numeric total_price` column; changing it to a derived display value
  needs a reconciled migration and has not been applied.
