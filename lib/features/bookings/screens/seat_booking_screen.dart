import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class SeatBookingScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? bookingData;
  const SeatBookingScreen({super.key, this.bookingData});

  @override
  ConsumerState<SeatBookingScreen> createState() => _SeatBookingScreenState();
}

class _SeatBookingScreenState extends ConsumerState<SeatBookingScreen> {
  final Set<int> _selectedSeats = {1};
  final Set<int> _occupiedSeats = {3}; // مقعد محجوز مسبقاً
  bool _isLoading = false;

  void _toggleSeat(int seatNumber) {
    if (_occupiedSeats.contains(seatNumber)) return;
    setState(() {
      if (_selectedSeats.contains(seatNumber)) {
        if (_selectedSeats.length > 1) {
          _selectedSeats.remove(seatNumber);
        }
      } else {
        _selectedSeats.add(seatNumber);
      }
    });
  }

  void _confirmBooking() {
    setState(() => _isLoading = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _isLoading = false);
      context.go('/passenger/booking-summary', extra: {
        'seatsCount': _selectedSeats.length,
        'driverName': widget.bookingData?['driverName'] ?? 'محمود السيد',
        'totalPrice': (_selectedSeats.length * (widget.bookingData?['price'] ?? 120)),
      });
    });
  }

  Widget _buildSeatWidget(int seatNumber, String label) {
    final isSelected = _selectedSeats.contains(seatNumber);
    final isOccupied = _occupiedSeats.contains(seatNumber);

    Color bgColor = Colors.transparent;
    Color iconColor = const Color(0xFF64748B);
    Color borderColor = const Color(0xFFE2E8F0);

    if (isOccupied) {
      bgColor = const Color(0xFFCBD5E1);
      iconColor = const Color(0xFF94A3B8);
      borderColor = Colors.transparent;
    } else if (isSelected) {
      bgColor = const Color(0xFFF59E0B);
      iconColor = Colors.white;
      borderColor = const Color(0xFFF59E0B);
    }

    return InkWell(
      onTap: isOccupied ? null : () => _toggleSeat(seatNumber),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 64,
        height: 72,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.airline_seat_recline_extra_rounded,
              color: iconColor,
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : iconColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final basePrice = widget.bookingData?['price'] ?? 120;
    final totalPrice = _selectedSeats.length * basePrice;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(AppStrings.confirmBooking(context)),
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
            Text(
              AppStrings.selectSeats(context),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.tr(context, ar: 'حدد المقاعد المفضلة لك داخل السيارة', en: 'Choose your desired seats inside the vehicle'),
              style: theme.textTheme.bodyMedium,
            ),

            const SizedBox(height: 24),

            // رسم بياني لمقاعد السيارة — مطابق لـ Figma
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                children: [
                  // الصف الأمامي (سائق + راكب أمامي)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // مقعد السائق (غير متاح)
                      Container(
                        width: 64,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.airline_seat_recline_normal_rounded, color: Color(0xFF0F172A), size: 26),
                            const SizedBox(height: 4),
                            Text(
                              AppStrings.driver(context),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                      // المقعد الأمامي
                      _buildSeatWidget(1, AppStrings.tr(context, ar: 'أمامي', en: 'Front')),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),

                  // الصف الخلفي (3 مقاعد)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSeatWidget(2, AppStrings.tr(context, ar: 'يسار', en: 'Left')),
                      _buildSeatWidget(3, AppStrings.tr(context, ar: 'وسط', en: 'Mid')),
                      _buildSeatWidget(4, AppStrings.tr(context, ar: 'يمين', en: 'Right')),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // دليل الألوان (Legend)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLegend(const Color(0xFFF59E0B), AppStrings.tr(context, ar: 'محدد', en: 'Selected')),
                      const SizedBox(width: 16),
                      _buildLegend(const Color(0xFFE2E8F0), AppStrings.tr(context, ar: 'متاح', en: 'Available')),
                      const SizedBox(width: 16),
                      _buildLegend(const Color(0xFFCBD5E1), AppStrings.tr(context, ar: 'محجوز', en: 'Booked')),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // طريقة الدفع
            Container(
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.payments_rounded, color: Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.paymentMethod(context),
                          style: TextStyle(fontSize: 11, color: theme.hintColor),
                        ),
                        Text(
                          AppStrings.cashToDriver(context),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ملخص المبلغ الإجمالي
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.totalAmount(context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$totalPrice ${AppStrings.currency(context)}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // زر تأكيد وإرسال طلب الحجز
            ElevatedButton(
              onPressed: _isLoading ? null : _confirmBooking,
              child: _isLoading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(AppStrings.confirmRequestBtn(context)),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

