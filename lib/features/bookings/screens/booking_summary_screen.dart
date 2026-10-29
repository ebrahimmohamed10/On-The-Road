import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class BookingSummaryScreen extends ConsumerWidget {
  final Map<String, dynamic>? summaryData;
  const BookingSummaryScreen({super.key, this.summaryData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final driverName = summaryData?['driverName'] ?? 'محمود السيد';
    final seatsCount = summaryData?['seatsCount'] ?? 1;
    final totalPrice = summaryData?['totalPrice'] ?? 120;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  LanguageThemeActions(),
                ],
              ),

              const Spacer(),

              // أيقونة النجاح
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF10B981),
                  size: 56,
                ),
              ),

              const SizedBox(height: 24),

              Text(
                AppStrings.bookingSuccess(context),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                AppStrings.bookingSuccessSub(context),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),

              const SizedBox(height: 32),

              // كارت تفاصيل الحجز
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppStrings.bookingCode(context),
                          style: TextStyle(fontSize: 12, color: theme.hintColor),
                        ),
                        const Text(
                          '#OTR-7821',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildSummaryRow(
                      AppStrings.driver(context),
                      driverName,
                      Icons.person_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryRow(
                      AppStrings.seatsCount(context),
                      '$seatsCount ${AppStrings.tr(context, ar: "مقاعد", en: "seats")}',
                      Icons.airline_seat_recline_extra_rounded,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryRow(
                      AppStrings.totalAmount(context),
                      '$totalPrice ${AppStrings.currency(context)}',
                      Icons.payments_outlined,
                      isPrice: true,
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // الأزرار السفلية
              ElevatedButton(
                onPressed: () {
                  context.go('/passenger/bookings');
                },
                child: Text(AppStrings.myTrips(context)),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: () {
                  context.go('/passenger/home');
                },
                child: Text(AppStrings.goToHome(context)),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, IconData icon, {bool isPrice = false}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFF59E0B)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isPrice ? 16 : 13,
            color: isPrice ? const Color(0xFFF59E0B) : null,
          ),
        ),
      ],
    );
  }
}

