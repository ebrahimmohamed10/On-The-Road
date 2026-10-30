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
      return service.getTrips(
        fromCity: filters['from'] as String?,
        toCity: filters['to'] as String?,
      );
    });

class TripService {
  final SupabaseClient _client;
  TripService(this._client);

  User? get currentUser => _client.auth.currentUser;

  /// جلب الرحلات الحية من سيرفر Supabase مع بيانات السائق والمقاطع
  Future<List<Map<String, dynamic>>> getTrips({
    String? fromCity,
    String? toCity,
  }) async {
    try {
      var query = _client
          .from('trips')
          .select('*, segments:trip_segments(*)')
          .eq('status', 'upcoming');

      if (fromCity != null && fromCity.isNotEmpty) {
        query = query.eq('origin_city', fromCity);
      }
      if (toCity != null && toCity.isNotEmpty) {
        query = query.eq('destination_city', toCity);
      }

      final trips = List<Map<String, dynamic>>.from(
        await query.order('departure_time', ascending: true),
      );
      if (trips.isEmpty) return trips;

      final driverIds = trips
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

      return trips.map((trip) {
        return {...trip, 'driver': driversById[trip['driver_id']]};
      }).toList();
    } catch (e) {
      // في حال حدوث خطأ أو عدم وجود شبكة، يُرجع قائمة فارغة
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
