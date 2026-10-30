import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Screens
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/hero_welcome_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/verification/screens/personal_details_screen.dart';
import '../../features/verification/screens/identity_verification_screen.dart';
import '../../features/verification/screens/driver_documents_screen.dart';
import '../../features/verification/screens/verification_submitted_screen.dart';
import '../../features/trips/screens/passenger_home_screen.dart';
import '../../features/trips/screens/search_trips_screen.dart';
import '../../features/trips/screens/ride_results_screen.dart';
import '../../features/trips/screens/trip_details_screen.dart';
import '../../features/trips/screens/booked_trip_details_screen.dart';
import '../../features/trips/screens/rate_trip_screen.dart';
import '../../features/bookings/screens/seat_booking_screen.dart';
import '../../features/bookings/screens/payment_screen.dart';
import '../../features/bookings/screens/booking_confirmation_screen.dart';
import '../../features/bookings/screens/my_bookings_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/chat/screens/chat_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      bool isAuth = false;
      try {
        final session = Supabase.instance.client.auth.currentSession;
        isAuth = session != null;
      } catch (_) {
        isAuth = false;
      }

      final isSplash = state.matchedLocation == '/splash';
      final isWelcome = state.matchedLocation == '/welcome';
      final isGoingToAuth = state.matchedLocation.startsWith('/auth');

      if (isSplash || isWelcome) return null;
      if (!isAuth && !isGoingToAuth) return '/welcome';
      if (isAuth && (isGoingToAuth || isWelcome)) return '/passenger/home';
      return null;
    },
    routes: [
      // Splash & Welcome
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const HeroWelcomeScreen()),

      // Auth Flow
      GoRoute(path: '/auth/login', builder: (_, _) =>  LoginScreen()),
      GoRoute(path: '/auth/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/auth/otp',
        builder: (_, state) {
          final phone = state.extra as String? ?? '';
          return OtpScreen(phone: phone);
        },
      ),

      // Verification Flow
      GoRoute(
        path: '/verification/personal-details',
        builder: (_, _) => const PersonalDetailsScreen(),
      ),
      GoRoute(
        path: '/verification/identity',
        builder: (_, _) => const IdentityVerificationScreen(),
      ),
      GoRoute(
        path: '/verification/driver-docs',
        builder: (_, _) => const DriverDocumentsScreen(),
      ),
      GoRoute(
        path: '/verification/submitted',
        builder: (_, _) => const VerificationSubmittedScreen(),
      ),

      // Passenger Flow
      GoRoute(path: '/passenger/home', builder: (_, _) => const PassengerHomeScreen()),
      GoRoute(path: '/passenger/search', builder: (_, _) => const SearchTripsScreen()),
      GoRoute(
        path: '/passenger/results',
        builder: (_, state) {
          final params = state.extra as Map<String, dynamic>?;
          return RideResultsScreen(searchParams: params);
        },
      ),
      GoRoute(
        path: '/passenger/trip-details',
        builder: (_, state) {
          final data = state.extra as Map<String, dynamic>?;
          return BookedTripDetailsScreen(tripData: data);
        },
      ),
      GoRoute(
        path: '/passenger/booked-trip/:id',
        builder: (_, state) {
          final data = state.extra as Map<String, dynamic>?;
          return BookedTripDetailsScreen(tripData: data);
        },
      ),
      GoRoute(
        path: '/passenger/trip/:id',
        builder: (_, state) {
          final data = state.extra as Map<String, dynamic>?;
          return TripDetailsScreen(
            tripId: state.pathParameters['id']!,
            tripData: data,
          );
        },
      ),
      GoRoute(
        path: '/passenger/book',
        builder: (_, state) {
          final data = state.extra as Map<String, dynamic>?;
          return SeatBookingScreen(bookingData: data);
        },
      ),
      GoRoute(
        path: '/passenger/payment',
        builder: (_, state) {
          final data = state.extra as Map<String, dynamic>?;
          return PaymentScreen(paymentData: data);
        },
      ),
      GoRoute(
        path: '/passenger/booking-confirmation',
        builder: (_, state) {
          final data = state.extra as Map<String, dynamic>?;
          return BookingConfirmationScreen(confirmationData: data);
        },
      ),
      GoRoute(
        path: '/passenger/booking-summary',
        builder: (_, state) {
          final data = state.extra as Map<String, dynamic>?;
          return BookingConfirmationScreen(confirmationData: data);
        },
      ),
      GoRoute(path: '/passenger/bookings', builder: (_, _) => const MyBookingsScreen()),
      GoRoute(path: '/passenger/profile',  builder: (_, _) => const ProfileScreen()),
      GoRoute(
        path: '/passenger/rate-trip',
        builder: (_, state) {
          final data = state.extra as Map<String, dynamic>?;
          return RateTripScreen(tripData: data);
        },
      ),

      // Chat
      GoRoute(
        path: '/chat/:bookingId',
        builder: (_, state) => ChatScreen(bookingId: state.pathParameters['bookingId']!),
      ),
    ],
  );
});
