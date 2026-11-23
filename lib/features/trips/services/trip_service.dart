import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final tripServiceProvider = Provider<TripService>((ref) {
  return TripService(Supabase.instance.client);
});

final availableTripsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, Map<String, dynamic>>((
      ref,
      filters,
    ) async {
      final service = ref.watch(tripServiceProvider);
      return service.searchTrips(
        originCityId: filters['fromCityId'] as String,
        destinationCityId: filters['toCityId'] as String,
        date: filters['date'] as DateTime,
        seats: filters['seats'] as int,
      );
    });

final myBookingsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, bool>((
      ref,
      past,
    ) async {
      final service = ref.watch(tripServiceProvider);
      return service.getMyBookings(past: past);
    });

class TripService {
  final SupabaseClient _client;
  TripService(this._client);

  User? get currentUser => _client.auth.currentUser;

  static const List<Map<String, dynamic>> _defaultCities = [
    {'id': 'cairo', 'code': 'CAI', 'name_ar': 'القاهرة', 'name_en': 'Cairo'},
    {'id': 'alexandria', 'code': 'ALY', 'name_ar': 'الإسكندرية', 'name_en': 'Alexandria'},
    {'id': 'giza', 'code': 'GZ', 'name_ar': 'الجيزة', 'name_en': 'Giza'},
    {'id': 'tanta', 'code': 'TAN', 'name_ar': 'طنطا', 'name_en': 'Tanta'},
    {'id': 'mansoura', 'code': 'MNS', 'name_ar': 'المنصورة', 'name_en': 'Mansoura'},
    {'id': 'ismailia', 'code': 'ISM', 'name_ar': 'الإسماعيلية', 'name_en': 'Ismailia'},
    {'id': 'suez', 'code': 'SUZ', 'name_ar': 'السويس', 'name_en': 'Suez'},
    {'id': 'portsaid', 'code': 'PSD', 'name_ar': 'بورسعيد', 'name_en': 'Port Said'},
    {'id': 'damanhour', 'code': 'DMH', 'name_ar': 'دمنهور', 'name_en': 'Damanhour'},
    {'id': 'banha', 'code': 'BNH', 'name_ar': 'بنها', 'name_en': 'Banha'},
    {'id': 'zagazig', 'code': 'ZGZ', 'name_ar': 'الزقازيق', 'name_en': 'Zagazig'},
    {'id': 'asyut', 'code': 'AT', 'name_ar': 'أسيوط', 'name_en': 'Asyut'},
    {'id': 'sohag', 'code': 'SHG', 'name_ar': 'سوهاج', 'name_en': 'Sohag'},
    {'id': 'qena', 'code': 'QNA', 'name_ar': 'قنا', 'name_en': 'Qena'},
    {'id': 'luxor', 'code': 'LXR', 'name_ar': 'الأقصر', 'name_en': 'Luxor'},
    {'id': 'aswan', 'code': 'ASW', 'name_ar': 'أسوان', 'name_en': 'Aswan'},
    {'id': 'hurghada', 'code': 'HRG', 'name_ar': 'الغردقة', 'name_en': 'Hurghada'},
    {'id': 'sharm', 'code': 'SSH', 'name_ar': 'شرم الشيخ', 'name_en': 'Sharm El Sheikh'},
  ];

  Future<List<Map<String, dynamic>>> getActiveCities() async {
    try {
      final rows = await _client
          .from('cities')
          .select('id, code, name_ar, name_en')
          .eq('is_active', true)
          .order('name_en');
      final list = List<Map<String, dynamic>>.from(rows);
      if (list.isNotEmpty) return list;
    } catch (_) {
      // In dev, test, or before DB seed, return complete Egyptian cities list
    }
    return _defaultCities;
  }

  /// Search by approved city stops, date range, and seat count in the database.
  Future<List<Map<String, dynamic>>> searchTrips({
    required String originCityId,
    required String destinationCityId,
    required DateTime date,
    required int seats,
  }) async {
    try {
      final startLocal = DateTime(date.year, date.month, date.day);
      final endLocal = startLocal.add(const Duration(days: 1));
      final matches = await _client.rpc(
        'search_trips',
        params: {
          'p_origin_city_id': originCityId,
          'p_destination_city_id': destinationCityId,
          'p_from': startLocal.toUtc().toIso8601String(),
          'p_to': endLocal.toUtc().toIso8601String(),
          'p_seats': seats,
        },
      );
      final summaries = List<Map<String, dynamic>>.from(matches as List);
      if (summaries.isEmpty) return const [];

      final tripIds = summaries
          .map((row) => row['trip_id'] as String)
          .toList(growable: false);
      final trips = await _client
          .from('trips')
          .select(
            '*, segments:trip_segments(*), '
            'stops:trip_stops(*, city:cities!trip_stops_city_fkey(*), '
            'stop:approved_stops!trip_stops_approved_stop_city_fkey(*)), '
            'fares:trip_fares(*)',
          )
          .eq('status', 'published')
          .inFilter('id', tripIds);
      final tripRows = List<Map<String, dynamic>>.from(trips);
      if (tripRows.isEmpty) return const [];

      final driverIds = tripRows
          .map((trip) => trip['driver_id'] as String)
          .toSet()
          .toList();
      final drivers = await _client
          .from('driver_public_profiles')
          .select(
            'id, name, avatar_url, rating, trips_count, car_model, car_color',
          )
          .inFilter('id', driverIds);
      final driversById = {
        for (final driver in drivers) driver['id'] as String: driver,
      };
      final tripsById = {
        for (final trip in tripRows) trip['id'] as String: trip,
      };

      return summaries
          .where((summary) => tripsById.containsKey(summary['trip_id']))
          .map((summary) {
            final trip = tripsById[summary['trip_id']]!;
            return {
              ...trip,
              'driver': driversById[trip['driver_id']],
              'search_seats_available': summary['seats_available'],
              'search_price_minor': summary['price_minor'],
            };
          })
          .toList(growable: false);
    } catch (e) {
      // Preserve the existing behavior for the results screen.
      return [];
    }
  }

  /// Creates a booking through the server-side atomic reservation RPC.
  Future<Map<String, dynamic>> createBooking({
    required String tripId,
    required String pickupCity,
    required String dropoffCity,
    required int seatsBooked,
  }) async {
    if (_client.auth.currentUser == null) {
      throw const BookingAuthException();
    }

    final result = await _client.rpc(
      'create_booking',
      params: {
        'p_trip_id': tripId,
        'p_pickup_city': pickupCity,
        'p_dropoff_city': dropoffCity,
        'p_seats_booked': seatsBooked,
      },
    );

    if (result is Map<String, dynamic>) return result;
    if (result is List && result.isNotEmpty && result.first is Map) {
      return Map<String, dynamic>.from(result.first as Map);
    }
    throw const FormatException('Booking RPC returned an unexpected response.');
  }

  /// Fetches passenger bookings from Supabase, split into Upcoming and Past.
  Future<List<Map<String, dynamic>>> getMyBookings({bool past = false}) async {
    final user = currentUser;
    if (user == null) return const [];

    try {
      final query = _client
          .from('bookings')
          .select(
            '*, trip:trips(*, driver:profiles!driver_id(id, name, avatar_url, rating, trips_count, car_model, car_color, car_plate))',
          )
          .eq('passenger_id', user.id);

      final List<dynamic> rows;
      if (past) {
        rows = await query
            .or('status.in.(completed,cancelled,rejected,no_show)')
            .order('created_at', ascending: false);
      } else {
        rows = await query
            .inFilter('status', ['pending', 'confirmed'])
            .order('created_at', ascending: false);
      }

      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      // In dev or if RLS restricts, return empty list gracefully
      return const [];
    }
  }

  /// Cancels an existing booking owned by the caller.
  Future<void> cancelBooking(String bookingId) async {
    final user = currentUser;
    if (user == null) throw const BookingAuthException();

    await _client
        .from('bookings')
        .update({'status': 'cancelled'})
        .eq('id', bookingId)
        .eq('passenger_id', user.id);
  }

  /// Submits a rating/review for a completed booking.
  Future<void> submitRating({
    required String bookingId,
    required int score,
    String? comment,
  }) async {
    final user = currentUser;
    if (user == null) throw const BookingAuthException();

    try {
      await _client.rpc(
        'submit_rating',
        params: {
          'p_booking_id': bookingId,
          'p_score': score,
          'p_comment': comment,
        },
      );
    } catch (_) {
      // Fallback: direct insert if RPC is not available or for demo bookings
      try {
        final booking = await _client
            .from('bookings')
            .select('trip:trips(driver_id)')
            .eq('id', bookingId)
            .maybeSingle();
        final driverId = booking?['trip']?['driver_id'];
        if (driverId != null) {
          await _client.from('ratings').insert({
            'booking_id': bookingId,
            'reviewer_id': user.id,
            'reviewee_id': driverId,
            'score': score,
            'comment': comment,
          });
        }
      } catch (_) {}
    }
  }
}

class BookingAuthException implements Exception {
  const BookingAuthException();
}
