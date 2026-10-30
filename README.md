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
2. Run the contents of `supabase_schema.sql` to create the tables, seat-availability function, and row-level security policies.
3. In `lib/core/constants/app_constants.dart`, set `supabaseUrl` and `supabaseAnonKey` to the project URL and its public client key. The application currently reads credentials from these source constants; it does **not** load `.env` files, `--dart-define` values, or other environment variables. Do not put a Supabase service-role key in the client app.
4. Start the app with `flutter run`.

The project has no implemented environment-variable configuration at this time. Externalize the public URL and client key before distributing builds, and review the RLS policies before using real user data. `sample_data.sql` is optional demo data; inspect it before running because it drops the `profiles.id` foreign-key constraint to permit sample driver IDs.

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
