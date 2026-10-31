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

class TripService {
  final SupabaseClient _client;
  TripService(this._client);

  User? get currentUser => _client.auth.currentUser;

  Future<List<Map<String, dynamic>>> getActiveCities() async {
    final rows = await _client
        .from('cities')
        .select('id, code, name_ar, name_en')
        .eq('is_active', true)
        .order('name_en');
    return List<Map<String, dynamic>>.from(rows);
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
      // Preserve the existing empty-state behavior for the results screen.
      return [];
    }
  }

  /// إنشاء حجز جديد في جدول bookings
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
}

class BookingAuthException implements Exception {
  const BookingAuthException();
}
