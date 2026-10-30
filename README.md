# On The Road — على الطريق

An Egypt-focused mobile ride-sharing (cost-sharing) app. Passengers can search for rides between cities, select seats, and submit a booking request. The project includes driver verification screens and is being built with Flutter and Supabase.

## Technology

- Flutter and Dart
- Supabase: PostgreSQL and Auth (backend integration is currently partial)
- Riverpod for app state
- GoRouter for navigation
- Flutter localization delegates with Arabic (RTL) and English (LTR) UI strings

## Requirements

- Flutter SDK compatible with the Dart constraint in `pubspec.yaml`
- A Supabase project for backend features
- A supported Flutter device or desktop target (for example, Android, Windows, or Chrome)

## Set up and run

From the repository root:

```sh
flutter pub get
flutter run
```

To select a target explicitly, use `flutter devices` and then, for example:

```sh
flutter run -d chrome
```

Run the available test suite with:

```sh
flutter test
```

## Supabase setup

1. Create a Supabase project and open its SQL Editor.
2. Run the contents of `supabase_schema.sql` to create the baseline tables and function.
3. Review the SQL in `supabase/migrations/` and run the migration files in timestamp order. They replace the baseline access policies with the Phase 1 policies and RPCs. Do not skip these migrations before using the client app.
4. Provide the project URL and public client key at build/run time. The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` using Dart compile-time environment declarations:

   ```sh
   flutter run \
     --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
   ```

   Do not put a Supabase `service_role` key in the client app. The public key is not a substitute for RLS.
5. Start the app with the same `--dart-define` values for your selected target.

The project uses Dart `--dart-define` values; `.env` files are not loaded. Review the RLS policies before using real user data. `sample_data.sql` is optional demo data; inspect it before running because it drops the `profiles.id` foreign-key constraint to permit sample driver IDs. Phase 1 migrations are review-only until you apply them yourself.

## Project structure

```text
lib/
  core/                 App constants, strings, routing, theme and locale state
  features/
    auth/                Welcome, sign-in, registration and OTP screens
    bookings/            Seat selection, payment and booking screens
    chat/                Chat screen
    profile/             Profile screen
    trips/               Passenger/driver trip screens and TripService
    verification/        Personal details and identity/document screens
  shared/widgets/        Shared navigation and language/theme controls
assets/images/           App image assets
supabase_schema.sql      Database schema, availability function and RLS policies
sample_data.sql          Optional demonstration records
test/                    Flutter tests
```

Some screens and backend flows are still prototypes; see `docs/BASELINE_AUDIT.md` for the audited baseline.
