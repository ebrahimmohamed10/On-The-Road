import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(Supabase.instance.client);
});

final notificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(notificationServiceProvider).getNotifications();
});

final unreadNotificationsCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(notificationServiceProvider).getUnreadCount();
});

class NotificationService {
  final SupabaseClient _client;

  NotificationService(this._client);

  User? get currentUser => _client.auth.currentUser;

  /// Fetches notifications for the current authenticated user.
  Future<List<Map<String, dynamic>>> getNotifications() async {
    final user = currentUser;
    if (user == null) return const [];

    try {
      final rows = await _client
          .from('notifications')
          .select('*')
          .eq('recipient_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(rows);
    } catch (_) {
      return const [];
    }
  }

  /// Gets unread notifications count.
  Future<int> getUnreadCount() async {
    final user = currentUser;
    if (user == null) return 0;

    try {
      final response = await _client
          .from('notifications')
          .select('id')
          .eq('recipient_id', user.id)
          .filter('read_at', 'is', null);

      return (response as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Marks a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    final user = currentUser;
    if (user == null) return;

    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('id', notificationId)
          .eq('recipient_id', user.id);
    } catch (_) {}
  }

  /// Marks all notifications as read for current user.
  Future<void> markAllAsRead() async {
    final user = currentUser;
    if (user == null) return;

    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toIso8601String()})
          .eq('recipient_id', user.id)
          .filter('read_at', 'is', null);
    } catch (_) {}
  }

  /// Subscribes to real-time notification events.
  RealtimeChannel? subscribeToNotifications({
    required void Function(Map<String, dynamic> notification) onNotification,
  }) {
    final user = currentUser;
    if (user == null) return null;

    final channel = _client.channel('notifications_${user.id}');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'recipient_id',
        value: user.id,
      ),
      callback: (payload) {
        final newRecord = payload.newRecord;
        if (newRecord.isNotEmpty) {
          onNotification(newRecord);
        }
      },
    ).subscribe();

    return channel;
  }
}
