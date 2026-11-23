import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  String _localizedText(BuildContext context, dynamic val) {
    if (val == null) return '';
    if (val is String) return val;
    if (val is Map) {
      final isAr = AppStrings.isArabic(context);
      return (isAr ? val['ar'] ?? val['en'] : val['en'] ?? val['ar'] ?? '').toString();
    }
    return val.toString();
  }

  String _formatTimeAgo(BuildContext context, dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final diff = DateTime.now().difference(dt);
      final isAr = AppStrings.isArabic(context);

      if (diff.inMinutes < 1) {
        return isAr ? 'الآن' : 'Just now';
      } else if (diff.inMinutes < 60) {
        return isAr ? 'منذ ${diff.inMinutes} دقيقة' : '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        return isAr ? 'منذ ${diff.inHours} ساعة' : '${diff.inHours}h ago';
      } else if (diff.inDays < 7) {
        return isAr ? 'منذ ${diff.inDays} يوم' : '${diff.inDays}d ago';
      } else {
        return '${dt.day}/${dt.month}';
      }
    } catch (_) {
      return '';
    }
  }

  IconData _iconForCategory(String? category) {
    switch (category?.toLowerCase()) {
      case 'booking':
        return Icons.confirmation_num_outlined;
      case 'trip':
        return Icons.directions_car_rounded;
      case 'message':
        return Icons.chat_bubble_outline_rounded;
      case 'safety':
        return Icons.shield_outlined;
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _colorForCategory(String? category) {
    switch (category?.toLowerCase()) {
      case 'booking':
        return const Color(0xFF10B981);
      case 'trip':
        return const Color(0xFFF59E0B);
      case 'message':
        return const Color(0xFF3B82F6);
      case 'safety':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notif) async {
    final notifId = notif['id']?.toString();
    if (notifId != null && notif['read_at'] == null) {
      await ref.read(notificationServiceProvider).markAsRead(notifId);
      ref.invalidate(notificationsProvider);
      ref.invalidate(unreadNotificationsCountProvider);
    }

    final data = notif['data'] as Map<String, dynamic>? ?? {};
    final category = notif['category']?.toString();

    if (!mounted) return;

    if (category == 'message' && data['booking_id'] != null) {
      context.push('/chat/${data['booking_id']}');
    } else if (data['booking_id'] != null) {
      context.push('/passenger/bookings');
    } else if (data['trip_id'] != null) {
      context.push('/driver/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final notificationsAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.notificationsTitle(context)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationServiceProvider).markAllAsRead();
              ref.invalidate(notificationsProvider);
              ref.invalidate(unreadNotificationsCountProvider);
            },
            child: Text(
              AppStrings.markAllRead(context),
              style: const TextStyle(
                color: Color(0xFFF59E0B),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(unreadNotificationsCountProvider);
        },
        child: notificationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(err.toString(), textAlign: TextAlign.center),
            ),
          ),
          data: (notifications) {
            if (notifications.isEmpty) {
              return _buildEmptyState(context, theme);
            }

            return ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: notifications.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final notif = notifications[index];
                final isUnread = notif['read_at'] == null;
                final category = notif['category']?.toString();
                final icon = _iconForCategory(category);
                final color = _colorForCategory(category);
                final title = _localizedText(context, notif['title']);
                final body = _localizedText(context, notif['body']);
                final timeStr = _formatTimeAgo(context, notif['created_at']);

                return InkWell(
                  onTap: () => _handleNotificationTap(notif),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUnread
                          ? (isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFFEF3C7).withValues(alpha: 0.35))
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isUnread
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                            : theme.dividerColor.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Category Icon
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        const SizedBox(width: 12),

                        // Title & Body
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                body,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (isUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.notifications_off_outlined,
            size: 44,
            color: Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppStrings.noNotificationsTitle(context),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.noNotificationsSub(context),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: theme.hintColor,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
