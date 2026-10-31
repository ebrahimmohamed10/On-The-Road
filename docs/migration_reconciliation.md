# ON THE ROAD — live/test schema reconciliation

Checked on 2026-11-01. This document describes the schema work performed on the
separate test project. Production was queried read-only and was not changed.

## Projects and Git safety point

- Production Supabase: `chwbyhqcmxedhfezdmfi` (`On The Road`, branch `main`).
- Test Supabase: `yzsjzvirbbelfxxrncey` (`On The Road Test`).
- Git branch: `codex/live-schema-reconciliation`.
- Existing checkpoint: `47f3f94 chore: snapshot backend work and document migrations`.
- No push to GitHub has been performed.
- Production cost metadata previously reported Free / $0 monthly quote. Confirm in
  the Supabase Billing UI if you need a billing guarantee.

## Production migration source

Production has 28 rows in `supabase_migrations.schema_migrations`; every row
contains its full SQL statement. Together they contain 275,250 SQL characters.
This made the migration-table replay route viable without installing the
Supabase CLI or Docker.

Two local files are not entries in the production ledger:

- `supabase/migrations/202610300001_security_profiles_rls.sql`
- `supabase/migrations/202610300002_atomic_segment_booking.sql`

The production record for `phase4b_booking_trip_workflows` requires
`trip_segments.segment_kind`, but no earlier recorded migration adds it. For
the test replay, only the needed column, check constraint, and unique indexes
from the local step-3 file were applied as
`test_prerequisite_trip_segment_kind`. The local file's older booking
functions were not copied; the later recorded workflow migration installs the
current functions.

Other live-only entries and version mismatches are recorded below. Do not run
`supabase db push` against production until migration history has been
reconciled deliberately.

| Live version | Local version | Name |
|---|---|---|
| `20261031170008` | — | `tighten_legacy_rls_and_driver_approval` |
| `20261031174208` | — | `private_identity_document_storage` |
| `20261031174542` | same | `identity_verification_requests` |
| `20261031214058` | `20261031220000` | `phase3_trip_stops_and_fares` |
| `20261031214345` | `20261031220500` | `phase3_availability_rpc_scope` |
| `20261031215127` | `20261031221000` | `phase4_booking_status_vocabulary` |
| `20261031215221` | `20261031221500` | `phase4_booking_workflows_history` |
| `20261031215645` | `20261031222000` | `phase5_pricing_snapshots` |
| `20261031215934` | `20261031222500` | `phase6_messaging_notifications_ratings_hardening` |
| `20261031220302` | `20261101000100` | `phase7_reports_support_retention_hardening` |
| `20261031220526` | `20261101000200` | `phase9_configurable_document_retention` |
| `20261031220635` | `20261101000300` | `phase9_fk_indexes` |
| `20261031213104` | same | `account_deletion_worker_schedule` (not replayed to test) |

The remaining live versions through `phase7b_final_hardening` are present in
the local directory with matching version/name. A matching name alone does not
make the differently numbered migrations safe to push.

## Test project replay result

The test project was built from the checked-in legacy baseline, an RLS
event-trigger setup, the test-only segment-kind prerequisite above, and the SQL
from 27 of the 28 live migration rows. The production worker schedule was
excluded because it hardcodes the production Edge Function URL. Its function,
tables, and retention schema are present in the test project; only that
project-specific cron job is absent.

The applied DDL now verifies as follows:

- Same 52 public base tables in production and test.
- Same 521 public columns and 70 public functions.
- `bookings` and `trip_segments` column lists match exactly.
- Test has the pending-booking expiry and trip-location purge cron jobs.
- Test does not have the production `account-deletion-worker` schedule.
- No test trips, segments, or bookings were present when the route/fare
  normalization migration removed the old text fare columns.

The test migration ledger uses new test-side timestamps and descriptive
`live_<source-version>_<name>` labels. It is not a direct copy of the
production migration ledger and must not be used to repair production history.

## Restorable SQL artifact

`docs/live_schema_snapshot.sql` is now a replayable schema script, not a
catalog-inventory query. It contains the checked-in baseline, the RLS event
trigger, the missing test prerequisite, and the exact SQL for 27 recorded live
migrations in order. It deliberately leaves out the production-specific
account-deletion cron schedule and documents that exception at the top.

It contains schema/DDL only. It does not contain user or trip data, Auth users,
Storage objects, Edge Function source or secrets, or project-level Realtime
publication configuration. Use it only to rebuild a clean test project; do not
run it on production.

## Booking implementation and next test

`create_booking` locks the trip row with `FOR UPDATE`, checks occupancy for
the requested route segment, and writes the booking and allocations in one
transaction. Its last-seat concurrency behavior has not yet been exercised.

Next, create test-only rider/driver accounts and a future trip with one seat.
Send two authenticated booking requests concurrently. Expected outcome: exactly
one pending booking is created, the other request is rejected for insufficient
seats, and no overbooking occurs. Then test cancellation/expiry to confirm the
seat is released. Do not use production identities or data for this test.

## Supabase advisor results on the reconstructed test project

- Security advisor: `public.bookings` has RLS enabled without a table policy.
  This may be intentional if all access is through narrow RPCs, but confirm
  Flutter does not need direct table reads.
- Security advisor: one anonymous-callable SECURITY DEFINER function,
  `get_shared_trip_status(text)`, and 41 authenticated-callable SECURITY
  DEFINER functions. These warnings were reproduced from production; they are
  not automatically proof of a vulnerability. Review each function's role
  checks and returned data, especially the public trip-share lookup.
- Performance advisor: 130 indexes are currently unused. The test database is
  empty, so this is expected and is not a reason to remove indexes now.

No advisor-driven permissions or schema changes were made during the replay.

## Related implementation notes

- The app calls `search_trips`; MVP search stays city/stop based. Distance
  search with PostGIS remains out of scope.
- Fare display uses integer minor units. Production still has
  `total_price_minor` alongside numeric `total_price`; removing or deriving
  the numeric value needs a separately reconciled migration.
- Shared-trip public output was narrowed to a short display name and driver
  image, with no rider personal data.
