# Phase 0 baseline audit

**Audit date:** 2026-10-30

**Scope:** Read-only review of app behavior, Supabase schema/policies, and current repository state. No app logic, schema, or RLS policy was changed.

## Execution results

- `flutter pub get` completed successfully: `Got dependencies!` It reported: `11 packages have newer versions incompatible with dependency constraints.` The output listed available newer releases for `code_assets`, `cross_file`, `cupertino_icons`, `hooks`, `material_color_utilities`, `meta`, `objective_c`, `record_use`, `shared_preferences_foundation`, `test_api`, and `vector_math`.
- `flutter test` passed: `00:00 +0: Smoke test - App builds properly` then `00:00 +1: All tests passed!`
- The test is only a trivial arithmetic assertion (`test/widget_test.dart:4-5`); it does not build or exercise this app.
- `flutter devices` found Windows desktop, Chrome, and Edge.
- The requested app launch was attempted with `flutter run -d windows`, but launch approval was rejected by the environment. **App build and runtime behavior are therefore not verified.** No build diagnostics were produced. Sandboxed Flutter CLI attempts stalled without output; dependency resolution and the test completed when run with the environment's approved elevated execution.

## Screen inventory

“Working” describes a functional UI interaction, not a production-backed user flow. “Partial” indicates a UI or flow with important backend/runtime behavior missing. Data-source references describe what the current screen actually reads or writes.

| Screen | File path | Status | Data source | Notes |
|---|---|---|---|---|
| Splash | `lib/features/auth/screens/splash_screen.dart` | Partial | Supabase Auth session state | Checks for a current session and routes onward; the session check is not proof that sign-in works. |
| Welcome | `lib/features/auth/screens/hero_welcome_screen.dart` | Working | Hard-coded UI assets/strings | Navigation to login and registration works; no backend data. |
| Onboarding | `lib/features/auth/screens/onboarding_screen.dart` | Partial | Hard-coded text/images | UI navigation only; it is not registered in `app_router.dart`. |
| Login | `lib/features/auth/screens/login_screen.dart` | Partial | Hard-coded delay; no Auth call | Validates a phone field and routes to OTP after a 600 ms delay. |
| Registration | `lib/features/auth/screens/register_screen.dart` | Partial | Local form state; no Auth/profile write | Role, name, and phone are collected; then navigation uses a delay. |
| OTP | `lib/features/auth/screens/otp_screen.dart` | Partial | Local OTP text fields; no Auth call | Any six-character code advances to verification after a delay. |
| Personal details | `lib/features/verification/screens/personal_details_screen.dart` | Partial | Local form state | Continues to identity screen; no profile persistence verified. |
| Identity verification | `lib/features/verification/screens/identity_verification_screen.dart` | Partial | Local camera image | Captures/previews a local image; no storage upload or verification request. |
| Driver documents | `lib/features/verification/screens/driver_documents_screen.dart` | Partial | Local image-picker files | Can select/preview images; submit is a delay/navigation, not Supabase Storage upload. |
| Verification submitted | `lib/features/verification/screens/verification_submitted_screen.dart` | Hard-coded demo data | Hard-coded UI | Static submission state; no request/status lookup. |
| Verification placeholder | `lib/features/verification/screens/verification_screen.dart` | Placeholder | Hard-coded UI | “Under construction” screen; not registered in the router. |
| Passenger home | `lib/features/trips/screens/passenger_home_screen.dart` | Hard-coded demo data | Hard-coded UI | Search/navigation works; displayed summary content is not loaded from Supabase. |
| Search trips | `lib/features/trips/screens/search_trips_screen.dart` | Partial | Local city/date/seat state | Sends search parameters onward. Results query currently uses only origin and destination city; date and seat count are not applied by `TripService`. |
| Ride results | `lib/features/trips/screens/ride_results_screen.dart` | Partial | Supabase `trips`, joined `profiles` and `trip_segments`; hard-coded fallback | Attempts a live query, but substitutes two demo rides for an empty result or a swallowed query error. Several displayed values are fixed/defaulted. |
| Trip details | `lib/features/trips/screens/trip_details_screen.dart` | Hard-coded demo data | Route extras plus hard-coded defaults | Route/time/stops and defaults are presentation data; no trip fetch by ID. |
| Create trip | `lib/features/trips/screens/create_trip_screen.dart` | Placeholder | Hard-coded UI | “Under construction”; no trip creation or route registration. |
| Driver home | `lib/features/trips/screens/driver_home_screen.dart` | Placeholder | Hard-coded UI | “Under construction”; no driver dashboard. |
| Booked trip details | `lib/features/trips/screens/booked_trip_details_screen.dart` | Hard-coded demo data | Route extras/default UI | No verified booking fetch/update; cancellation and chat affordances do not demonstrate backend actions. |
| Rate trip | `lib/features/trips/screens/rate_trip_screen.dart` | Partial | Local form state | Rating submission waits briefly and navigates; no rating table/write exists in the schema. |
| Seat booking | `lib/features/bookings/screens/seat_booking_screen.dart` | Partial | Local seat state and hard-coded occupied seats/default route values | Seat choices are not fetched or reserved; passes defaults for trip and route. |
| Payment | `lib/features/bookings/screens/payment_screen.dart` | Partial | Route extras/defaults; Supabase `bookings` insert attempt | Payment method selection is UI only. Booking write result is ignored and confirmation always follows. |
| Booking confirmation | `lib/features/bookings/screens/booking_confirmation_screen.dart` | Hard-coded demo data | Route extras/defaults | Displays a success-style confirmation and generated-looking booking code; not proof of successful persistence. |
| Booking summary | `lib/features/bookings/screens/booking_summary_screen.dart` | Hard-coded demo data | Hard-coded UI | Static confirmation-like screen; router's `/passenger/booking-summary` route instead builds `BookingConfirmationScreen`. |
| My bookings | `lib/features/bookings/screens/my_bookings_screen.dart` | Hard-coded demo data | Hard-coded sample booking cards | Upcoming/past tabs render fixed entries; no `bookings` query. |
| Chat | `lib/features/chat/screens/chat_screen.dart` | Placeholder | Hard-coded UI plus booking ID | Displays “under construction”; no `messages` read, insert, or realtime subscription. |
| Profile | `lib/features/profile/screens/profile_screen.dart` | Hard-coded demo data | Hard-coded UI | No profile fetch/update or Auth sign-out call verified in this screen. |

## Earlier review findings

| Finding | Verdict | Evidence and qualification |
|---|---|---|
| Trip search reads from Supabase. | **Partially** | `TripService.getTrips` queries `trips` and joins driver profiles and segments (`lib/features/trips/services/trip_service.dart:21-42`); `RideResultsScreen` calls it (`lib/features/trips/screens/ride_results_screen.dart:54-59`). On empty/error it shows fallback rides (`ride_results_screen.dart:84-86`); the service catches all errors and returns an empty list (`trip_service.dart:43-46`). Search does not apply date/seat criteria. |
| Login and OTP verification are simulated, not using Supabase Auth. | **Confirmed** | Login waits 600 ms and routes to OTP (`lib/features/auth/screens/login_screen.dart:24-34`). OTP checks code length and routes onward after a delay (`lib/features/auth/screens/otp_screen.dart:31-40`). Neither calls Auth. Registration also only delays and navigates (`lib/features/auth/screens/register_screen.dart:28-37`). |
| Driver home, trip creation, chat, and booking list are placeholders or hard-coded. | **Confirmed** | Driver home/create trip/chat show “under construction” (`lib/features/trips/screens/driver_home_screen.dart:3-11`, `create_trip_screen.dart:3-11`, `lib/features/chat/screens/chat_screen.dart:3-12`). Booking list embeds fixed cards and sample trip details (`lib/features/bookings/screens/my_bookings_screen.dart:56-100` and subsequent card data); no Supabase query is present. |
| Booking confirmation shows success even if saving fails. | **Confirmed** | `PaymentScreen` awaits `createBooking` inside an empty catch, ignores its boolean result, then always routes to confirmation (`lib/features/bookings/screens/payment_screen.dart:36-61`). The service converts insert exceptions to `false` (`trip_service.dart:72-75`). |
| A fallback passenger ID is used in the booking service. | **Confirmed** | `lib/features/trips/services/trip_service.dart:60-66` uses a fixed UUID when `currentUser` is null. |
| Booking flow uses defaults instead of the selected trip, pickup/drop-off points, and actual segment price. | **Partially** | Some trip values are passed through, but seat booking defaults the trip ID/price and hard-codes Cairo/Alexandria (`lib/features/bookings/screens/seat_booking_screen.dart:32-44`). Payment again defaults these values (`payment_screen.dart:28-34`). Ride results picks `segments.last.price` rather than resolving the requested segment and hard-codes departure/arrival time (`lib/features/trips/screens/ride_results_screen.dart:64-81`). Trip details uses hard-coded route/time values (`lib/features/trips/screens/trip_details_screen.dart:20-22`, `64-80`). |
| `available_seats` exists but the app never calls it; booking insert does not reserve seats atomically. | **Confirmed** | SQL defines the function at `supabase_schema.sql:81-104`. No Dart call/RPC exists; `TripService.createBooking` directly inserts a row (`trip_service.dart:50-71`). There is no transaction/locking/conditional capacity check around that insert in the schema. |
| Schema permits public reads of all profiles. | **Confirmed** | RLS is enabled for all five tables (`supabase_schema.sql:109-113`); `Public read profiles` uses `FOR SELECT USING (true)` at line 118. This policy is table-wide, so it is not limited to the selected profile columns in the app query. The profile table includes national ID and document URL fields (`supabase_schema.sql:15-19`). |

## RLS policy inventory

These are all policies declared in `supabase_schema.sql`; RLS is enabled on each listed table at lines 109-113.

| Table | Policies declared | Baseline implication |
|---|---|---|
| `profiles` | `Public read profiles` — SELECT `USING (true)` (line 118); `Users can update own profile` — UPDATE `USING (auth.uid() = id)` (line 121). | Any client can select profile rows under this policy, including sensitive columns. Own-row UPDATE does not restrict which columns may be changed (for example role/verification fields). No INSERT policy is declared. |
| `trips` | `Public read trips` — SELECT `USING (true)` (line 116). | Reads are public; no client INSERT/UPDATE/DELETE policy is declared, so driver trip creation/update is not enabled by this schema. |
| `trip_segments` | `Public read segments` — SELECT `USING (true)` (line 117). | Reads are public; no client write policy is declared. |
| `bookings` | `Users can view own bookings` — SELECT `USING (auth.uid() = passenger_id)` (line 122); `Users can create bookings` — INSERT `WITH CHECK (auth.uid() = passenger_id)` (line 123); `Drivers can view trip bookings` — SELECT for trip's driver (lines 124-126). | No client UPDATE/DELETE policies are declared for accept/reject/cancel flows. |
| `messages` | **No policies declared.** | RLS is enabled with no client policies, so client reads and writes are denied by default. |

No storage buckets or storage policies are declared in this SQL file.

## Other risks and broken/incomplete areas

- **No environment-variable handling:** Supabase URL and publishable client key are source constants (`lib/core/constants/app_constants.dart:7-9`). The key is a publishable client key, not a service-role secret, but client-side access still depends on correctly restrictive RLS.
- **Profile privacy and privilege escalation risk:** The public profile SELECT policy exposes all row columns at the database API, including national ID and identity document URLs. The own-profile UPDATE policy has no column-level restriction; a user may be able to edit role/verification values unless additional database controls exist outside this schema. Those controls were not verified.
- **No write policies for trips/segments and no messages policies:** Driver publishing and chat cannot be backed by the provided schema policies. The UI doesn't currently implement those writes either.
- **Availability function logic needs review:** It sums every overlapping booking into one total (`supabase_schema.sql:92-100`) and subtracts that from total capacity. For multi-leg trips this can count bookings on different non-overlapping legs together, so it is not a reliable per-segment maximum. It is also not used by the app.
- **Booking statuses diverge:** SQL defaults new bookings to `pending` (`supabase_schema.sql:63-65`), while the app insert explicitly sends `confirmed` (`lib/features/trips/services/trip_service.dart:63-71`). No driver approval flow is implemented.
- **Errors can be hidden by demo content:** `getTrips` catches all errors and returns an empty list (`trip_service.dart:43-46`); results then render hard-coded rides (`ride_results_screen.dart:84-86`), masking backend/configuration problems.
- **Sample data changes schema security assumptions:** `sample_data.sql:5-6` drops the profiles-to-Auth foreign key to allow demo users. This should not be run against a real project without understanding the impact. No Supabase project connection or deployed database state was inspected.
- **Booking confirmation is not a payment:** The selected cash/Vodafone Cash/card choice is UI-only. There is no payment provider integration in the reviewed source/schema.
- **Routing/flow gaps:** Onboarding, driver home, trip creation, the generic verification placeholder, and booking summary are not used as expected by registered routes. The app currently has no usable driver publishing flow.
- **No end-to-end coverage:** The only test is a standalone arithmetic smoke assertion (`test/widget_test.dart:4-5`).

## Limits

This audit reflects checked-in/current local source and the schema file only. The Supabase project was not queried, so deployed policies, tables, storage buckets, Auth settings, and actual network behavior are **not verified**. App launch/build diagnostics are **not verified** because environment approval to launch the Windows app was rejected. No app, schema, or policy fixes were made in Phase 0.
