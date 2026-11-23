import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/notification_bell_button.dart';
import '../services/trip_service.dart';

class PassengerHomeScreen extends ConsumerWidget {
  const PassengerHomeScreen({super.key});

  String _formatDateTime(BuildContext context, dynamic dateTimeVal) {
    if (dateTimeVal == null) return '';
    try {
      final dt = DateTime.parse(dateTimeVal.toString()).toLocal();
      final isAr = AppStrings.isArabic(context);
      final arMonths = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      final enMonths = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final monthName = isAr ? arMonths[dt.month - 1] : enMonths[dt.month - 1];
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = isAr ? (dt.hour >= 12 ? 'م' : 'ص') : (dt.hour >= 12 ? 'PM' : 'AM');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '${dt.day} $monthName • $hour:$minute $period';
    } catch (_) {
      return dateTimeVal.toString();
    }
  }

  Widget _buildEmptyUpcoming(BuildContext context, ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded, size: 36, color: theme.hintColor.withValues(alpha: 0.5)),
          const SizedBox(height: 10),
          Text(
            AppStrings.tr(context, ar: 'لا توجد رحلات قادمة حالياً', en: 'No upcoming trips right now'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.hintColor),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.tr(context, ar: 'احجز رحلتك القادمة بين المحافظات الآن بسهولة', en: 'Book your next intercity ride easily'),
            style: TextStyle(fontSize: 12, color: theme.hintColor.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final upcomingAsync = ref.watch(myBookingsProvider(false));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 30,
              height: 30,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 10),
            Text(AppStrings.appName(context)),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: const [
          NotificationBellButton(),
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.tr(context, ar: 'أهلاً بك 👋', en: 'Welcome 👋'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              AppStrings.tr(context, ar: 'إلى أين وجهتك القادمة اليوم؟', en: 'Where are you heading today?'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // بطاقة البحث عن رحلة
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  InkWell(
                    onTap: () => context.push('/passenger/search'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.trip_origin_rounded, color: Color(0xFF10B981), size: 20),
                          const SizedBox(width: 12),
                          Text(
                            AppStrings.fromCity(context),
                            style: TextStyle(color: theme.hintColor, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  InkWell(
                    onTap: () => context.push('/passenger/search'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded, color: Color(0xFFEF4444), size: 20),
                          const SizedBox(width: 12),
                          Text(
                            AppStrings.toCity(context),
                            style: TextStyle(color: theme.hintColor, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  ElevatedButton.icon(
                    onPressed: () => context.push('/passenger/search'),
                    icon: const Icon(Icons.search_rounded),
                    label: Text(AppStrings.searchRidesBtn(context)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // قسم رحلاتي القادمة
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.upcoming(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () => context.go('/passenger/bookings'),
                  child: Text(
                    AppStrings.tr(context, ar: 'عرض الكل', en: 'View all'),
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // كارت رحلة قادمة حي من سوبابيز
            upcomingAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (_, __) => _buildEmptyUpcoming(context, theme),
              data: (bookings) {
                if (bookings.isEmpty) {
                  return _buildEmptyUpcoming(context, theme);
                }
                final booking = bookings.first;
                final trip = booking['trip'] as Map<String, dynamic>? ?? {};
                final driver = trip['driver'] as Map<String, dynamic>? ?? {};
                final from = booking['pickup_city']?.toString() ??
                    trip['origin_city']?.toString() ??
                    'القاهرة';
                final to = booking['dropoff_city']?.toString() ??
                    trip['destination_city']?.toString() ??
                    'الإسكندرية';
                final dateStr = _formatDateTime(context, trip['departure_time'] ?? booking['created_at']);
                final seats = (booking['seats_booked'] as num?)?.toInt() ?? 1;
                final driverName = driver['name']?.toString() ??
                    (AppStrings.isArabic(context) ? 'أحمد حسن' : 'Ahmed Hassan');
                final car = driver['car_model']?.toString() ?? 'تويوتا كورولا';
                final status = booking['status']?.toString() ?? 'confirmed';

                final rawPrice = booking['total_price'] ?? booking['total_price_minor'];
                final int price;
                if (rawPrice is num) {
                  price = rawPrice > 1000 ? (rawPrice / 100).round() : rawPrice.round();
                } else {
                  price = 180;
                }

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
                      'status': AppStrings.confirmedStatus(context),
                      'rawStatus': status,
                      'seats': seats,
                      'isPast': false,
                    });
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.directions_car_rounded, color: Color(0xFFF59E0B)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$from ➔ $to',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$dateStr • $seats ${AppStrings.tr(context, ar: "مقاعد", en: "seats")}',
                                style: TextStyle(fontSize: 12, color: theme.hintColor),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            AppStrings.confirmedStatus(context),
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }
}
