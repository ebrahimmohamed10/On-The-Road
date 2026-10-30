import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../trips/services/trip_service.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? paymentData;

  const PaymentScreen({
    super.key,
    this.paymentData,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  int _selectedMethod = 0; // 0 = Cash, 1 = Vodafone Cash, 2 = Card
  bool _isLoading = false;

  Future<void> _onConfirmAndSend() async {
    setState(() => _isLoading = true);

    final fromCity = widget.paymentData?['from'] ?? 'القاهرة';
    final toCity = widget.paymentData?['to'] ?? 'الإسكندرية';
    final driverName = widget.paymentData?['driverName'] ?? 'أحمد حسن';
    final seatsCount = (widget.paymentData?['seatsCount'] as num?)?.toInt() ?? 1;
    final pricePerSeat = (widget.paymentData?['price'] as num?)?.toInt() ?? 180;
    final totalPrice = seatsCount * pricePerSeat;
    final tripId = widget.paymentData?['tripId'] ?? 'aaaa1111-1111-1111-1111-111111111111';

    // حفظ الحجز في Supabase
    try {
      final service = ref.read(tripServiceProvider);
      await service.createBooking(
        tripId: tripId,
        pickupCity: fromCity,
        dropoffCity: toCity,
        seatsBooked: seatsCount,
        totalPrice: totalPrice.toDouble(),
      );
    } catch (_) {}

    if (!mounted) return;
    setState(() => _isLoading = false);

    context.go('/passenger/booking-confirmation', extra: {
      'from': fromCity,
      'to': toCity,
      'driverName': driverName,
      'seatsCount': seatsCount,
      'pricePerSeat': pricePerSeat,
      'totalPrice': totalPrice,
      'date': widget.paymentData?['date'] ?? 'الأربعاء ٢٨ أكتوبر',
      'time': widget.paymentData?['time'] ?? '08:30 ص',
      'bookingCode': '#OTR-2841',
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    final fromCity = widget.paymentData?['from'] ?? (isArabic ? 'القاهرة' : 'Cairo');
    final toCity = widget.paymentData?['to'] ?? (isArabic ? 'الإسكندرية' : 'Alexandria');
    final driverName = widget.paymentData?['driverName'] ?? (isArabic ? 'أحمد حسن' : 'Ahmed Hassan');
    final seatsCount = (widget.paymentData?['seatsCount'] as num?)?.toInt() ?? 1;
    final pricePerSeat = (widget.paymentData?['price'] as num?)?.toInt() ?? 180;
    final total = seatsCount * pricePerSeat;

    final dateText = isArabic ? 'الأربعاء ٢٨ أكتوبر · ٨:٣٠ ص' : 'Wed, 28 Oct · 8:30 AM';
    final driverInitials = isArabic ? 'أح' : 'AH';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            isArabic ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_new_rounded,
            size: 20,
          ),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/passenger/home');
            }
          },
        ),
        title: Text(
          AppStrings.payment(context),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================
            // 1. كارت ملخص مسار الرحلة والسائق في الأعلى
            // ==========================================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // خط السير
                  Row(
                    children: [
                      Text(
                        '$fromCity ➔ $toCity',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // التاريخ والميعاد
                  Text(
                    dateText,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.hintColor,
                    ),
                  ),
                  const Divider(height: 20),
                  // السائق
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          driverInitials,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        driverName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ==========================================
            // 2. قسم طرق الدفع (طريقة الدفع)
            // ==========================================
            Text(
              AppStrings.paymentMethod(context),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),

            // خيار 1: كاش للسائق (Cash to driver)
            _buildPaymentMethodOption(
              index: 0,
              icon: Icons.payments_outlined,
              iconBgColor: const Color(0xFFFEF3C7),
              iconColor: const Color(0xFFD97706),
              title: AppStrings.cashToDriver(context),
              subtitle: AppStrings.payWhenYouBoard(context),
            ),

            const SizedBox(height: 10),

            // خيار 2: فودافون كاش (Vodafone Cash)
            _buildPaymentMethodOption(
              index: 1,
              icon: Icons.smartphone_rounded,
              iconBgColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              iconColor: const Color(0xFF64748B),
              title: AppStrings.vodafoneCash(context),
            ),

            const SizedBox(height: 10),

            // خيار 3: كارت بنكي (Bank card)
            _buildPaymentMethodOption(
              index: 2,
              icon: Icons.credit_card_rounded,
              iconBgColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              iconColor: const Color(0xFF64748B),
              title: AppStrings.bankCard(context),
            ),

            const SizedBox(height: 24),

            // ==========================================
            // 3. كارت تفاصيل الحسبة المالية (Price Breakdown)
            // ==========================================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                children: [
                  // عدد المقاعد × السعر
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.seatCalc(context, seatsCount, pricePerSeat),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      Text(
                        '$total ${AppStrings.currency(context)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // رسوم الخدمة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.serviceFee(context),
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.hintColor,
                        ),
                      ),
                      Text(
                        '0 ${AppStrings.currency(context)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),

                  // الإجمالي
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.total(context),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '$total ${AppStrings.currency(context)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // لا رسوم خفية
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: theme.hintColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AppStrings.noHiddenFees(context),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.hintColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ==========================================
            // 4. الزر الكحلي: تأكيد وإرسال الطلب
            // ==========================================
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              onPressed: _isLoading ? null : _onConfirmAndSend,
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      AppStrings.confirmAndSendRequest(context),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  Widget _buildPaymentMethodOption({
    required int index,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final isSelected = _selectedMethod == index;

    return InkWell(
      onTap: () => setState(() => _selectedMethod = index),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : theme.dividerColor.withValues(alpha: 0.15),
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: Row(
          children: [
            // الأيقونة
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),

            // النصوص
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // دائرة الاختيار (Radio indicator)
            Icon(
              isSelected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: isSelected ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

