import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../../../shared/widgets/notification_bell_button.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../trips/services/trip_service.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return const Color(0xFF10B981); // Emerald green
      case 'pending':
        return const Color(0xFFF59E0B); // Amber
      case 'completed':
        return const Color(0xFF64748B); // Slate
      case 'cancelled':
      case 'rejected':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFFF59E0B);
    }
  }

  String _statusLabel(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
        return AppStrings.confirmedStatus(context);
      case 'pending':
        return AppStrings.pendingStatus(context);
      case 'completed':
        return AppStrings.completedStatus(context);
      case 'cancelled':
        return AppStrings.tr(context, ar: 'ملغي', en: 'Cancelled');
      case 'rejected':
        return AppStrings.tr(context, ar: 'مرفوض', en: 'Rejected');
      default:
        return status;
    }
  }

  String _formatDateTime(dynamic dateTimeVal) {
    if (dateTimeVal == null) return '';
    try {
      final dt = DateTime.parse(dateTimeVal.toString()).toLocal();
      final months = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      final monthName = months[dt.month - 1];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = dt.hour >= 12 ? 'م' : 'ص';
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} $monthName • $hour:$minute $period';
    } catch (_) {
      return dateTimeVal.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcomingAsync = ref.watch(myBookingsProvider(false));
    final pastAsync = ref.watch(myBookingsProvider(true));

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.myTrips(context)),
        automaticallyImplyLeading: false,
        actions: const [
          NotificationBellButton(),
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF59E0B),
          labelColor: const Color(0xFFF59E0B),
          unselectedLabelColor: theme.hintColor,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: [
            Tab(text: AppStrings.upcoming(context)),
            Tab(text: AppStrings.past(context)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ─── Upcoming Trips ───
          _buildBookingsTab(
            context: context,
            asyncValue: upcomingAsync,
            past: false,
            emptyTitle: AppStrings.tr(
              context,
              ar: 'لا توجد رحلات قادمة حالياً',
              en: 'No upcoming trips right now',
            ),
            emptySubtitle: AppStrings.tr(
              context,
              ar: 'ابحث عن رحلتك القادمة بين المحافظات بسهولة وأمان.',
              en: 'Find and book your next intercity ride easily and safely.',
            ),
          ),

          // ─── Past Trips ───
          _buildBookingsTab(
            context: context,
            asyncValue: pastAsync,
            past: true,
            emptyTitle: AppStrings.tr(
              context,
              ar: 'لا توجد رحلات سابقة',
              en: 'No past trips yet',
            ),
            emptySubtitle: AppStrings.tr(
              context,
              ar: 'ستظهر هنا جميع رحلاتك المكتملة وسجل حجوزاتك السابقة.',
              en: 'All your completed and past rides will appear here.',
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  Widget _buildBookingsTab({
    required BuildContext context,
    required AsyncValue<List<Map<String, dynamic>>> asyncValue,
    required bool past,
    required String emptyTitle,
    required String emptySubtitle,
  }) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myBookingsProvider(past));
      },
      child: asyncValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => _buildErrorState(context, err.toString(), past),
        data: (bookings) {
          if (bookings.isEmpty) {
            return _buildEmptyState(context, emptyTitle, emptySubtitle);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final booking = bookings[index];
              return _buildRealTripCard(context, booking, past: past);
            },
          );
        },
      ),
    );
  }

  Widget _buildRealTripCard(
    BuildContext context,
    Map<String, dynamic> booking, {
    required bool past,
  }) {
    final theme = Theme.of(context);
    final trip = booking['trip'] as Map<String, dynamic>? ?? {};
    final driver = trip['driver'] as Map<String, dynamic>? ?? {};

    final from = booking['pickup_city']?.toString() ??
        trip['origin_city']?.toString() ??
        'القاهرة';
    final to = booking['dropoff_city']?.toString() ??
        trip['destination_city']?.toString() ??
        'الإسكندرية';
    final dateStr = _formatDateTime(trip['departure_time'] ?? booking['created_at']);
    final driverName = driver['name']?.toString() ??
        (AppStrings.isArabic(context) ? 'أحمد حسن' : 'Ahmed Hassan');
    final car = driver['car_model']?.toString() ?? 'تويوتا كورولا';
    final seats = (booking['seats_booked'] as num?)?.toInt() ?? 1;

    final rawPrice = booking['total_price'] ?? booking['total_price_minor'];
    final int price;
    if (rawPrice is num) {
      price = rawPrice > 1000 ? (rawPrice / 100).round() : rawPrice.round();
    } else {
      price = 180;
    }

    final status = booking['status']?.toString() ?? (past ? 'completed' : 'confirmed');
    final statusColor = _statusColor(status);
    final statusText = _statusLabel(context, status);

    return InkWell(
      onTap: () {
        context.push('/passenger/trip-details', extra: {
          'bookingId': booking['id']?.toString(),
          'bookingRef': '#OTR-${(booking['id']?.toString().substring(0, 4) ?? '2841').toUpperCase()}',
          'driverName': driverName,
          'driverInitials': driverName.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join(),
          'driverRating': driver['rating']?.toString() ?? '4.9',
          'tripsCount': driver['trips_count']?.toString() ?? '126',
          'carModel': car,
          'price': price,
          'from': from,
          'to': to,
          'date': dateStr,
          'status': statusText,
          'seats': seats,
          'isPast': past,
        });
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$from ➔ $to',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              dateStr,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 16,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 6),
                    Text('$driverName • $car', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                Text(
                  '$price ${AppStrings.currency(context)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
            if (!past) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () {
                      context.push('/chat/${booking['id']}', extra: {
                        'bookingId': booking['id']?.toString(),
                        'driverName': driverName,
                        'route': '$from ➔ $to',
                        'carModel': car,
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 14,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppStrings.messageDriver(context),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car_filled_rounded,
                color: Color(0xFFF59E0B),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => context.push('/passenger/search'),
              icon: const Icon(Icons.search_rounded),
              label: Text(AppStrings.searchRidesBtn(context)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error, bool past) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(
              AppStrings.tr(
                context,
                ar: 'تعذر تحميل الرحلات في الوقت الحالي.',
                en: 'Could not load trips at this time.',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ref.invalidate(myBookingsProvider(past)),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppStrings.tr(context, ar: 'إعادة المحاولة', en: 'Retry')),
            ),
          ],
        ),
      ),
    );
  }
}
