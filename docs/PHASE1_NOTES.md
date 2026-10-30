# Phase 1 implementation notes

## Database baseline and migrations

The local `supabase_schema.sql` defines five public tables. Before applying the Phase 1 migration, their RLS state and policies were:

| Table | RLS before Phase 1 | Existing policies |
|---|---|---|
| `profiles` | Enabled | `Public read profiles` (SELECT `USING (true)`); `Users can update own profile` (UPDATE where `auth.uid() = id`). |
| `trips` | Enabled | `Public read trips` (SELECT `USING (true)`). |
| `trip_segments` | Enabled | `Public read segments` (SELECT `USING (true)`). |
| `bookings` | Enabled | `Users can view own bookings` (SELECT); `Users can create bookings` (INSERT); `Drivers can view trip bookings` (SELECT). |
| `messages` | Enabled | No policies declared. |

`supabase/migrations/202610300001_security_profiles_rls.sql` replaces policies on those five tables, enables RLS on every public base/partitioned table present when run, restricts grants, and creates the profile trigger and driver view. The legacy `supabase_schema.sql` should be treated as the initial table-definition script; review and apply the migration files after it, in timestamp order. The migration has **not** been applied to any Supabase project.

### Phase 1 policy intent

- **Profiles:** authenticated users may select, insert, and update rows whose `id` is their `auth.uid()`. Column grants omit updates to `role`, `verification_status`, `rating`, and Auth-managed `phone`; insert grants omit these fields too. Auth metadata is filtered in the profile-creation trigger so only `passenger` and `driver` can be selected at registration; all other roles become `passenger`.
- **Driver directory:** `driver_public_profiles` is a dedicated, authenticated-only view of approved drivers. It returns only `id`, `name`, `avatar_url`, `rating`, `trips_count`, `car_model`, and `car_color`. It does not return phone, national ID, document URLs, role, or verification status. The view uses PostgreSQL's default security-definer view behavior (explicitly `security_invoker = false`) so it can read rows hidden by profiles RLS; its projection and predicate are deliberately narrow. Review this view whenever the public driver fields change.
- **Trips:** authenticated users can select `upcoming` trips. Insert/update policies require the authenticated ID to match `driver_id` and the caller's profile role to be `driver`. `driver_id` is not update-granted, preventing ownership transfer through ordinary client updates.
- **Trip segments:** authenticated users can read segments only when their trip is upcoming. Client segment writes remain disabled; driver publishing is outside Phase 1.
- **Bookings:** authenticated passengers can read their own rows; the owning driver can read rows for their trips. Direct client inserts are revoked and booking creation is restricted to the RPC described below. A passenger can only update `status` on their own pending/confirmed booking, and the row policy permits only `cancelled`; other booking columns have no client update grant.
- **Messages:** RLS is enabled and client access is revoked with no policies. Chat authorization is deferred with the chat feature.
- **Helper functions:** `is_own_trip` is a narrowly scoped `SECURITY DEFINER` predicate used so the driver booking-read policy can recognize ownership even when the trip is not currently open. It returns only a boolean and checks `auth.uid()` internally. The auth trigger function is also `SECURITY DEFINER` so it can create a profile as part of the Auth user insert. Both functions use an empty fixed `search_path`, fully qualified object names, and restricted execute grants.

The repository contains no storage bucket definitions or `storage.objects` policies. Verification images in the current app are local image-picker files; the source does not upload them. Existing deployed Storage buckets/policies were not inspected and are not verified.

## Phone OTP setup

The app sends only phone OTP requests through Supabase Auth; it does not contain an email OTP path. Phone values are normalized to E.164: local Egyptian mobile numbers such as `01111915092` become `+201111915092`; spaces and hyphens are removed. Arabic-Indic digits are normalized. Unsupported prefixes, lengths, and non-Egyptian numbers are rejected before sending.

### Hosted Supabase test numbers

1. Open the Supabase Dashboard and select the project.
2. Go to **Authentication → Sign In / Providers → Phone** and enable the Phone provider.
3. Under **Test Phone Numbers and OTPs**, enter each test number in international format without `+` or spaces, paired with a fixed code as `201111915092=123456`. Use two different numbers for the two-account checks below.
4. Set **Test OTPs Valid Until** and save.
5. Use each test number and its configured code in the app. Do not add test numbers or OTPs to app source.

Supabase's current hosted-project guide says a test number skips SMS delivery, but still says an SMS provider must be configured for Phone Auth. If the dashboard requires one, configure an SMS provider before testing; no SMS should be sent for matching test-number requests. Remove test numbers or set an expiry before production.

### Later: real SMS delivery with Twilio

When ready to send real SMS, go to **Authentication → Sign In / Providers → Phone**, select/configure Twilio, and supply the Twilio Account SID, Auth Token, and Messaging Service SID (or the provider fields currently shown in the Dashboard). Create/configure the Twilio messaging service and sender for the destination countries, then test delivery and adjust Auth rate limits/CAPTCHA. Keep these provider credentials only in Supabase's server-side Dashboard configuration. The Flutter code continues using `signInWithOtp(phone: ...)` and `verifyOTP(type: OtpType.sms, ...)`; switching the provider requires no app code change. Remove or expire fixed test numbers before enabling production traffic.

## App configuration

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` with `String.fromEnvironment`. Run locally with:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
```

The second value must be the public publishable/anon key. Never pass `service_role` to a Flutter build. `.env` files are not loaded.

## Segment model and atomic booking

Migration `202610300002_atomic_segment_booking.sql` adds nullable `trip_segments.segment_kind` with two allowed values:

- `leg`: one physical adjacent stop-to-stop leg. `segment_order = N` connects route stop N to stop N+1. Only these rows participate in seat occupancy.
- `fare_override`: a fare for the exact `(from_city, to_city)` pair. It is never a physical leg and never participates in occupancy.

Existing rows are not updated by the migration. Their `segment_kind` stays NULL and `create_booking` rejects a trip with any unclassified row. Before enabling bookings for existing trips, inspect and explicitly classify each row as `leg` or `fare_override`; do not classify solely from order or assume a long-distance row is a leg. New sample rows in `sample_data.sql` explicitly mark Cairo→Tanta and Tanta→Alexandria as `leg`, and Cairo→Alexandria as `fare_override`.

The RPC accepts only trip ID, pickup city, drop-off city, and seat count. It requires `auth.uid()`, locks the trip row with `FOR UPDATE`, validates route stop order, checks every adjacent leg from pickup through (but excluding) drop-off, and inserts the booking in the same transaction. A direct Cairo→Alexandria fare row cannot double-count as another occupancy leg. For pricing, an exact fare override takes precedence; otherwise the RPC sums the adjacent-leg prices. The client does not submit a passenger ID, order numbers, price, or status. The RPC inserts `pending` status. Direct client booking inserts remain revoked.

`create_booking` is `SECURITY DEFINER` because the authenticated client cannot insert directly and the RPC must both see overlapping bookings hidden by passenger/driver RLS and insert the row. It uses `SET search_path = ''`, fully qualified objects, derives the passenger from `auth.uid()`, and is executable only by `authenticated`. The replacement `available_seats` helper also considers only `leg` rows. Both it and the RPC derive an existing booking interval from pickup/drop-off city names and adjacent-leg order, rather than trusting legacy order numbers. Older bookings with correct city values therefore occupy the matching legs without row mutation. Review legacy bookings with missing or incorrect city values before relying on their occupancy. Booking uses its own checks while holding the trip lock, so its availability decision and insert are serialized.

The migration does not touch `supabase_schema.sql` or live Supabase. On a development project, review and apply the base schema, then migrations `202610300001...` and `202610300002...` in order, then seed only if desired. The sample seed labels its inserted rows, but it does not classify already-existing rows. Review `sample_data.sql` before using it: it drops the profiles-to-auth.users foreign key and inserts demo UUIDs, which is not suitable for an Auth-backed development project as-is.
### App booking flow

Search results no longer fall back to demo trips. The selected trip payload carries its `id` and classified adjacent legs into stop selection; the passenger chooses pickup, drop-off, and seat count before continuing. The app calls only `create_booking` and does not submit price, order numbers, passenger ID, or status. The displayed confirmation requires the returned booking ID and server total; failed RPC requests remain on the payment/confirmation step with an error. The payment-choice UI is still presentation only: Phase 1 creates a pending booking request and does not charge money or integrate a payment provider.
## Manual validation checklist

After applying the reviewed migrations to a development Supabase project and running the app with two configured test numbers:

1. Register two accounts on two different Egyptian test phone numbers. Verify the fixed OTP on each, then confirm each `auth.users` row receives a matching `profiles` row and each user can read only their own profile.
2. From account A, attempt to select account B's profile directly. It must return no row or permission denied. Confirm driver discovery returns only the public fields in `driver_public_profiles` and never includes phone, national ID, license/document URLs, role, or verification status.
3. As account A, attempt to insert/update a profile row for B and attempt to update A's role, verification status, or rating. Each attempt must be denied.
4. Sign out and open `/passenger/book` or `/passenger/payment` as a deep link. The app must route to login; an unauthenticated Data API call to `create_booking` must be denied.
5. Attempt a direct booking insert from a client. It must be denied. Call `create_booking` only after all route rows are explicitly classified.
6. With sample trip `aaaa1111-1111-1111-1111-111111111111`, book Cairo to Tanta: the fare should be 60 and one seat should be reserved on adjacent leg 1 only. Book Tanta to Alexandria: the fare should be 70 and one seat should be reserved on adjacent leg 2 only.
7. Book Cairo to Alexandria on that same sample trip: the exact-pair fare override should be 120 (not 60+70), while occupancy must still reserve both adjacent legs 1 and 2. Confirm the fare override row itself is not counted as an occupancy leg.
8. For overlap, set a development trip to one remaining seat, create a full-route Cairo to Alexandria booking, then attempt a Cairo to Tanta or Tanta to Alexandria booking from a second account/device. The later overlapping partial booking must fail. Also issue two simultaneous requests for the final seat; at most one may succeed.
9. Confirm a no-seat/invalid-route RPC failure shows an error and does not navigate to the success screen. Confirm an RPC success displays the returned booking ID and server total.
10. Check Supabase Dashboard > Storage for any existing buckets and policies. This repository defines none, so inspect deployed Storage separately before uploading verification documents.
## Verification state

The Phase 1 SQL migrations are review-only and have not been run against any Supabase project. Auth requires a hosted project with Phone Auth configured; no live OTP, RLS, trigger, view, RPC, Storage, or concurrency behavior is verified. The VS Code Problems diagnostics reported no issues in the six changed Dart files. `flutter analyze` and `flutter test` each ran for over 60 seconds without producing output and were interrupted; build, app launch, and tests are therefore Not verified.
