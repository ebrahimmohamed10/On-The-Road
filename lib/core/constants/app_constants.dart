class AppConstants {
  AppConstants._();

  static const String appName = 'On the Road';
  static const String appNameAr = 'على الطريق';

  // Supply public client configuration at build/run time. Never use a
  // Supabase service_role key in a Flutter client.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const bool isSupabaseConfigured =
      supabaseUrl != '' && supabaseAnonKey != '';

  // Verification statuses
  static const String verifUnverified = 'unverified';
  static const String verifPending = 'pending';
  static const String verifApproved = 'approved';
  static const String verifRejected = 'rejected';
  static const String verifResubmission = 'resubmission_required';

  // Booking statuses
  static const String bookingPending = 'pending';
  static const String bookingConfirmed = 'confirmed';
  static const String bookingRejected = 'rejected';
  static const String bookingCancelled = 'cancelled';
  static const String bookingCompleted = 'completed';
  static const String bookingNoShow = 'no_show';

  // Trip statuses
  static const String tripUpcoming = 'upcoming';
  static const String tripActive = 'active';
  static const String tripCompleted = 'completed';
  static const String tripCancelled = 'cancelled';

  // User roles
  static const String rolePassenger = 'passenger';
  static const String roleDriver = 'driver';
  static const String roleAdmin = 'admin';
}
