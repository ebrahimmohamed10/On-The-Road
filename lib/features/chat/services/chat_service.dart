import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(Supabase.instance.client);
});

final conversationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(chatServiceProvider).getConversations();
});

final messagesProvider = FutureProvider.family
    .autoDispose<List<Map<String, dynamic>>, String>((ref, bookingId) async {
  return ref.watch(chatServiceProvider).getMessages(bookingId);
});

class ChatService {
  final SupabaseClient _client;

  ChatService(this._client);

  User? get currentUser => _client.auth.currentUser;

  /// Fetches all active conversations for the current authenticated user.
  Future<List<Map<String, dynamic>>> getConversations() async {
    final user = currentUser;
    if (user == null) return const [];

    try {
      // 1. Fetch from public.conversations
      final convRows = await _client
          .from('conversations')
          .select('''
            id,
            booking_id,
            trip_id,
            rider_id,
            driver_id,
            created_at,
            updated_at,
            booking:bookings(id, status, pickup_city, dropoff_city, created_at),
            trip:trips(id, origin_city, destination_city, departure_time),
            rider:profiles!rider_id(id, name, avatar_url, phone),
            driver:profiles!driver_id(id, name, avatar_url, phone, car_model)
          ''')
          .or('rider_id.eq.${user.id},driver_id.eq.${user.id}')
          .order('updated_at', ascending: false);

      final List<Map<String, dynamic>> conversations =
          List<Map<String, dynamic>>.from(convRows);

      // 2. Also fetch confirmed bookings to guarantee any booking without a conversation row is represented
      final existingBookingIds = conversations
          .map((c) => c['booking_id']?.toString())
          .whereType<String>()
          .toSet();

      final bookingRows = await _client
          .from('bookings')
          .select('''
            id,
            trip_id,
            passenger_id,
            status,
            pickup_city,
            dropoff_city,
            created_at,
            trip:trips(id, origin_city, destination_city, departure_time, driver_id, driver:profiles!driver_id(id, name, avatar_url, phone, car_model))
          ''')
          .eq('passenger_id', user.id)
          .inFilter('status', ['confirmed', 'completed', 'pending'])
          .order('created_at', ascending: false);

      for (final b in bookingRows) {
        final bId = b['id']?.toString();
        if (bId != null && !existingBookingIds.contains(bId)) {
          final trip = b['trip'] as Map<String, dynamic>? ?? {};
          final driver = trip['driver'] as Map<String, dynamic>? ?? {};
          conversations.add({
            'id': bId,
            'booking_id': bId,
            'trip_id': b['trip_id'],
            'rider_id': user.id,
            'driver_id': trip['driver_id'],
            'created_at': b['created_at'],
            'updated_at': b['created_at'],
            'booking': {
              'id': bId,
              'status': b['status'],
              'pickup_city': b['pickup_city'],
              'dropoff_city': b['dropoff_city'],
            },
            'trip': {
              'id': b['trip_id'],
              'origin_city': trip['origin_city'],
              'destination_city': trip['destination_city'],
              'departure_time': trip['departure_time'],
            },
            'driver': driver,
            'rider': {
              'id': user.id,
              'name': user.userMetadata?['name'] ?? 'أنا',
            },
          });
        }
      }

      // 3. Attach latest message for each conversation
      for (final conv in conversations) {
        final bookingId = conv['booking_id']?.toString();
        if (bookingId != null) {
          final lastMsg = await _client
              .from('messages')
              .select('id, content, sender_id, created_at')
              .eq('booking_id', bookingId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();
          if (lastMsg != null) {
            conv['last_message'] = lastMsg;
          }
        }
      }

      return conversations;
    } catch (e) {
      // In case of network error or RLS during guest mode
      return const [];
    }
  }

  /// Fetches message history for a specific booking.
  Future<List<Map<String, dynamic>>> getMessages(String bookingId) async {
    final user = currentUser;
    if (user == null) return const [];

    try {
      final rows = await _client
          .from('messages')
          .select('''
            id,
            booking_id,
            sender_id,
            content,
            created_at,
            sender:profiles!sender_id(id, name, avatar_url)
          ''')
          .eq('booking_id', bookingId)
          .order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      return const [];
    }
  }

  /// Sends a message inside a booking thread.
  Future<Map<String, dynamic>?> sendMessage({
    required String bookingId,
    required String content,
  }) async {
    final user = currentUser;
    if (user == null) throw const ChatAuthException('User is not signed in');

    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;

    try {
      // Primary: Call the secure RPC function
      final res = await _client.rpc(
        'send_message',
        params: {
          'p_booking_id': bookingId,
          'p_content': trimmed,
        },
      );
      if (res is Map<String, dynamic>) return res;
      if (res is List && res.isNotEmpty) {
        return Map<String, dynamic>.from(res.first as Map);
      }
      return {
        'booking_id': bookingId,
        'sender_id': user.id,
        'content': trimmed,
        'created_at': DateTime.now().toIso8601String(),
      };
    } catch (_) {
      // Fallback: Direct insert if RPC is not available or during client tests
      try {
        final inserted = await _client
            .from('messages')
            .insert({
              'booking_id': bookingId,
              'sender_id': user.id,
              'content': trimmed,
            })
            .select()
            .single();
        return inserted;
      } catch (insertError) {
        rethrow;
      }
    }
  }

  /// Realtime subscription for incoming messages in a booking thread.
  RealtimeChannel subscribeToMessages({
    required String bookingId,
    required void Function(Map<String, dynamic> message) onNewMessage,
  }) {
    final channelName = 'messages_$bookingId';
    final channel = _client.channel(channelName);

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'booking_id',
        value: bookingId,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          onNewMessage(newRecord);
        }
      },
    ).subscribe();

    return channel;
  }
}

class ChatAuthException implements Exception {
  final String message;
  const ChatAuthException(this.message);

  @override
  String toString() => message;
}
