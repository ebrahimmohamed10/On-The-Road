import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final tripServiceProvider = Provider<TripService>((ref) {
  return TripService(Supabase.instance.client);
});

final availableTripsProvider = FutureProvider.family<List<Map<String, dynamic>>, Map<String, dynamic>>((ref, filters) async {
  final service = ref.watch(tripServiceProvider);
  return service.getTrips(
    fromCity: filters['from'] as String?,
    toCity: filters['to'] as String?,
  );
});

class TripService {
  final SupabaseClient _client;
  TripService(this._client);

  /// جلب الرحلات الحية من سيرفر Supabase مع بيانات السائق والمقاطع
  Future<List<Map<String, dynamic>>> getTrips({
    String? fromCity,
    String? toCity,
  }) async {
    try {
      var query = _client.from('trips').select('''
        *,
        driver:profiles!driver_id (
          id, name, avatar_url, rating, trips_count, car_model, car_color
        ),
        segments:trip_segments (*)
      ''').eq('status', 'upcoming');

      if (fromCity != null && fromCity.isNotEmpty) {
        query = query.eq('origin_city', fromCity);
      }
      if (toCity != null && toCity.isNotEmpty) {
        query = query.eq('destination_city', toCity);
      }

      final response = await query.order('departure_time', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      // في حال حدوث خطأ أو عدم وجود شبكة، يُرجع قائمة فارغة
      return [];
    }
  }

  /// إنشاء حجز جديد في جدول bookings
  Future<bool> createBooking({
    required String tripId,
    required String pickupCity,
    required String dropoffCity,
    required int seatsBooked,
    required double totalPrice,
    int pickupOrder = 1,
    int dropoffOrder = 2,
  }) async {
    try {
      final user = _client.auth.currentUser;
      final passengerId = user?.id ?? 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';

      await _client.from('bookings').insert({
        'trip_id': tripId,
        'passenger_id': passengerId,
        'pickup_city': pickupCity,
        'dropoff_city': dropoffCity,
        'pickup_order': pickupOrder,
        'dropoff_order': dropoffOrder,
        'seats_booked': seatsBooked,
        'total_price': totalPrice,
        'status': 'confirmed',
      });
      return true;
    } catch (e) {
      return false;
    }
  }
}
