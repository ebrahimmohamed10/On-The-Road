import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../../../shared/widgets/app_bottom_nav.dart';

class BookingConfirmationScreen extends ConsumerWidget {
  final Map<String, dynamic>? confirmationData;

  const BookingConfirmationScreen({
    super.key,
    this.confirmationData,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    final fromCity = confirmationData?['from'] ?? (isArabic ? 'القاهرة' : 'Cairo');
    final toCity = confirmationData?['to'] ?? (isArabic ? 'الإسكندرية' : 'Alexandria');
    final driverName = confirmationData?['driverName'] ?? (isArabic ? 'أحمد حسن' : 'Ahmed Hassan');
    final seatsCount = (confirmationData?['seatsCount'] as num?)?.toInt() ?? 1;
    final totalPrice = (confirmationData?['totalPrice'] as num?)?.toInt() ?? 180;
    final bookingCode = confirmationData?['bookingCode'] ?? '#OTR-2841';

    final dateHeader = isArabic ? 'الأربعاء ٢٨ أكتوبر ٢٠٢٦' : 'Wed, 28 Oct 2026';
    final driverInitials = isArabic ? 'أح' : 'AH';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          AppStrings.requestSent(context),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        centerTitle: true,
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          children: [
            const SizedBox(height: 12),

            // ==========================================
            // 1. الدائرة الخضراء وعبارة نجاح إرسال الطلب
            // ==========================================
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                color: Color(0xFF16A34A),
                size: 38,
              ),
            ),
            const SizedBox(height: 18),

            Text(
              AppStrings.bookingRequestSent(context),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),

            Text(
              AppStrings.weWillNotifyDriver(context),
              style: TextStyle(
                fontSize: 13,
                color: theme.hintColor,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 24),

            // ==========================================
            // 2. كارت تذكرة الرحلة التفصيلي (Trip Ticket)
            // ==========================================
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // رأس الكارت: التاريخ + شارة "في انتظار السائق"
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dateHeader,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFFD97706),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppStrings.waitingForDriver(context),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD97706),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // المسار الزمني (Timeline: Cairo -> Alexandria)
                  _buildTimelineStop(
                    context,
                    time: '08:30',
                    cityName: fromCity,
                    stationName: isArabic ? 'محطة رمسيس' : 'Ramses Station',
                    isOrigin: true,
                  ),

                  // الخط الرأسي الرابط بين المحطتين
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 11),
                    child: Container(
                      width: 2,
                      height: 28,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),

                  _buildTimelineStop(
                    context,
                    time: '11:00',
                    cityName: toCity,
                    stationName: isArabic ? 'محطة سيدي جابر' : 'Sidi Gaber Station',
                    isOrigin: false,
                  ),

                  const Divider(height: 28),

                  // بيانات السائق والتقييم والسعر
                  Row(
                    children: [
                      // صورة / حروف السائق
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          driverInitials,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // اسم السائق والتفاصيل
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppStrings.yourDriverForTrip(context),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // التقييم والسعر
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 3),
                              const Text(
                                '4.9',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                AppStrings.seatCountLabel(context, seatsCount),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$totalPrice ${AppStrings.currency(context)}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // رقم الحجز
            Text(
              AppStrings.bookingRef(context, bookingCode),
              style: TextStyle(
                fontSize: 12,
                color: theme.hintColor,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 28),

            // ==========================================
            // 3. أزرار التحكم السفلية
            // ==========================================
            // الزر الرئيسي: عرض رحلاتي
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: () {
                context.go('/passenger/bookings');
              },
              child: Text(
                AppStrings.viewMyTrips(context),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // الزر الثانوي: الرجوع للرئيسية
            TextButton(
              onPressed: () {
                context.go('/passenger/home');
              },
              child: Text(
                AppStrings.backToHome(context),
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  Widget _buildTimelineStop(
    BuildContext context, {
    required String time,
    required String cityName,
    required String stationName,
    required bool isOrigin,
  }) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // النقطة الملونة
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: isOrigin ? const Color(0xFFF59E0B) : const Color(0xFF1E293B),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: (isOrigin ? const Color(0xFFF59E0B) : const Color(0xFF1E293B))
                    .withValues(alpha: 0.3),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),

        // اسم المدينة والمحطة
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cityName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                stationName,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),

        // التوقيت
        Text(
          time,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: theme.hintColor,
          ),
        ),
      ],
    );
  }
}
