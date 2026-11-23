import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../services/trip_service.dart';

class BookedTripDetailsScreen extends ConsumerWidget {
  final Map<String, dynamic>? tripData;

  const BookedTripDetailsScreen({super.key, this.tripData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final driverName = tripData?['driverName'] ?? (AppStrings.isArabic(context) ? 'أحمد حسن' : 'Ahmed Hassan');
    final driverInitials = tripData?['driverInitials'] ?? (AppStrings.isArabic(context) ? 'أح' : 'AH');
    final driverRating = tripData?['driverRating'] ?? '4.9';
    final tripsCount = tripData?['tripsCount'] ?? '126';
    final carDetails = tripData?['carModel'] ?? AppStrings.defaultCarDetails(context);
    final bookingRef = tripData?['bookingRef'] ?? '#OTR-2841';
    final price = tripData?['price'] ?? 180;
    final dateHeader = tripData?['date'] ?? AppStrings.defaultDateHeader(context);

    final pickupTime = tripData?['pickupTime'] ?? (AppStrings.isArabic(context) ? '٠٨:٣٠ ص' : '8:30 AM');
    final pickupStation = tripData?['pickupStation'] ?? (tripData?['from'] ?? AppStrings.ramsesStation(context));
    final pickupCity = tripData?['pickupCity'] ?? (tripData?['from'] ?? AppStrings.cairoCity(context));

    final dropoffTime = tripData?['dropoffTime'] ?? (AppStrings.isArabic(context) ? '١١:٠٠ ص' : '11:00 AM');
    final dropoffStation = tripData?['dropoffStation'] ?? (tripData?['to'] ?? AppStrings.sidiGaberStation(context));
    final dropoffCity = tripData?['dropoffCity'] ?? (tripData?['to'] ?? AppStrings.alexCity(context));

    final rawStatus = tripData?['rawStatus']?.toString().toLowerCase() ??
        (tripData?['isPast'] == true ? 'completed' : 'confirmed');
    final Color statusColor;
    final String statusLabel;
    switch (rawStatus) {
      case 'confirmed':
        statusColor = const Color(0xFF10B981);
        statusLabel = AppStrings.confirmedStatus(context);
        break;
      case 'pending':
        statusColor = const Color(0xFFF59E0B);
        statusLabel = AppStrings.pendingStatus(context);
        break;
      case 'completed':
        statusColor = const Color(0xFF64748B);
        statusLabel = AppStrings.completedStatus(context);
        break;
      case 'cancelled':
      case 'rejected':
        statusColor = const Color(0xFFEF4444);
        statusLabel = rawStatus == 'rejected'
            ? AppStrings.tr(context, ar: 'مرفوض', en: 'Rejected')
            : AppStrings.tr(context, ar: 'ملغي', en: 'Cancelled');
        break;
      default:
        statusColor = const Color(0xFF10B981);
        statusLabel = AppStrings.confirmedStatus(context);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          AppStrings.tripDetails(context),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 22),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppStrings.tripLinkCopied(context)),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF0F172A),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ==========================================
            // Card 1: Booking Status & Reference Header
            // ==========================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dateHeader,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          statusLabel,
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
                    AppStrings.bookingRef(context, bookingRef),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ==========================================
            // Card 2: Route & Timeline
            // ==========================================
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dateHeader,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: theme.hintColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppStrings.tripDuration(context),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Timeline Stepper (Pickup -> Dropoff)
                  _buildTimelineItem(
                    time: pickupTime,
                    station: pickupStation,
                    city: pickupCity,
                    dotColor: const Color(0xFFF59E0B),
                    showBottomLine: true,
                    theme: theme,
                  ),
                  _buildTimelineItem(
                    time: dropoffTime,
                    station: dropoffStation,
                    city: dropoffCity,
                    dotColor: isDark ? Colors.white : const Color(0xFF0F172A),
                    showBottomLine: false,
                    theme: theme,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ==========================================
            // Card 3: Driver Profile & Vehicle
            // ==========================================
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Driver Info Row
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFEEF2FF),
                        child: Text(
                          driverInitials,
                          style: const TextStyle(
                            color: Color(0xFF4F46E5),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 15,
                                  color: Color(0xFFF59E0B),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '$driverRating • $tripsCount ${AppStrings.tr(context, ar: 'رحلة', en: 'trips')}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.hintColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Verification Badges Row
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      // Badge 1: ID Verified
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7).withValues(alpha: isDark ? 0.2 : 0.6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              size: 13,
                              color: Color(0xFFD97706),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              AppStrings.idVerified(context),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD97706),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Badge 2: Valid License
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5).withValues(alpha: isDark ? 0.2 : 0.6),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_rounded,
                              size: 13,
                              color: Color(0xFF059669),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              AppStrings.validLicense(context),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // Car Info
                  Row(
                    children: [
                      Icon(
                        Icons.directions_car_outlined,
                        size: 16,
                        color: theme.hintColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          carDetails,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Action Buttons: Message Driver & Call
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.push(
                            '/chat/${tripData?['bookingId'] ?? 'inbox'}',
                            extra: tripData,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: BorderSide(
                              color: theme.dividerColor.withValues(alpha: 0.25),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppStrings.messageDriver(context),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _showCallDialog(context, driverName);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: BorderSide(
                              color: theme.dividerColor.withValues(alpha: 0.25),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            AppStrings.callDriver(context),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ==========================================
            // Card 4: Your Safety (أمانك)
            // ==========================================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2411) : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFDE68A).withValues(alpha: isDark ? 0.3 : 0.8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 18, color: Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      Text(
                        AppStrings.yourSafety(context),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Button 1: Share Trip Live
                  InkWell(
                    onTap: () => _shareTripWithTrusted(context, ref, pickupCity, dropoffCity, driverName),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.share_location_rounded,
                            size: 18,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppStrings.shareTripWithTrusted(context),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFD97706)),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 14),
                  // Button 2: Emergency SOS
                  InkWell(
                    onTap: () => _showEmergencySheet(context),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.emergency_outlined,
                            size: 18,
                            color: Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              AppStrings.emergencyButton(context),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFEF4444)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ==========================================
            // Card 5: Payment Summary
            // ==========================================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 15,
                            color: theme.hintColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            AppStrings.paymentCashToDriver(context),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.total(context),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '$price ${AppStrings.currency(context)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ==========================================
            // Cancellation / Completed Actions
            // ==========================================
            if (rawStatus == 'completed') ...[
              ElevatedButton.icon(
                onPressed: () {
                  context.push(
                    '/passenger/rate-trip',
                    extra: {
                      'bookingId': tripData?['bookingId'],
                      'driverName': driverName,
                      'initials': driverInitials,
                      'route': '$pickupCity ← $dropoffCity',
                      'dateLabel': dateHeader,
                    },
                  );
                },
                icon: const Icon(Icons.star_rounded, color: Color(0xFFF59E0B)),
                label: Text(
                  AppStrings.rateYourTrip(context),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ] else if (rawStatus == 'cancelled') ...[
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cancel_outlined, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.tr(context, ar: 'تم إلغاء هذا الحجز', en: 'This booking has been cancelled'),
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Center(
                child: TextButton(
                  onPressed: () => _showCancellationPolicyDialog(context),
                  child: Text(
                    AppStrings.cancellationPolicy(context),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () => _showCancelBookingConfirmation(context, ref),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  AppStrings.cancelBooking(context),
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  Widget _buildTimelineItem({
    required String time,
    required String station,
    required String city,
    required Color dotColor,
    required bool showBottomLine,
    required ThemeData theme,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot and dashed line
          Column(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              if (showBottomLine)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: theme.dividerColor.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),

          // Time Column
          SizedBox(
            width: 78,
            child: Text(
              time,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),

          // Station & City Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  city,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.hintColor,
                  ),
                ),
                if (showBottomLine) const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCallDialog(BuildContext context, String driverName) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              driverName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            const SizedBox(height: 8),
            const Text(
              '+20 101 234 5678',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFFF59E0B),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.phone_rounded),
              label: Text(AppStrings.callDriver(context)),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCancellationPolicyDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.cancellationPolicy(context),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 14),
            Text(
              AppStrings.cancelBookingSub(context),
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: const Color(0xFF0F172A),
              ),
              child: Text(AppStrings.tr(context, ar: 'فهمت ذلك', en: 'Got it')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareTripWithTrusted(
    BuildContext context,
    WidgetRef ref,
    String pickupCity,
    String dropoffCity,
    String driverName,
  ) async {
    final bookingId = tripData?['bookingId']?.toString();
    if (bookingId == null) return;
    final isAr = AppStrings.isArabic(context);
    final copiedMsg = AppStrings.trackingLinkCopied(context);

    try {
      final token = await ref.read(tripServiceProvider).createTripShare(bookingId);
      final trackingUrl = 'https://ontheroad.app/track/$token';
      final shareText = isAr
          ? 'أنا مسافر الآن في رحلة عبر تطبيق "على الطريق" من $pickupCity إلى $dropoffCity مع الكابتن $driverName. يمكنك متابعة مسار رحلتي مباشرة من هنا:\n$trackingUrl'
          : 'I am traveling on an intercity ride with On The Road from $pickupCity to $dropoffCity with driver $driverName. Track my ride live here:\n$trackingUrl';

      await Clipboard.setData(ClipboardData(text: shareText));

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(copiedMsg)),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {}
  }

  void _showEmergencySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emergency_outlined, color: Color(0xFFEF4444), size: 24),
                  const SizedBox(width: 10),
                  Text(
                    AppStrings.emergencySheetTitle(context),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.emergencySheetSub(context),
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEE2E2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_police_outlined, color: Color(0xFFDC2626)),
                ),
                title: Text(
                  AppStrings.policeEmergency(context),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.phone, size: 14),
                  label: const Text('122'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.medical_services_outlined, color: Color(0xFFD97706)),
                ),
                title: Text(
                  AppStrings.ambulanceEmergency(context),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.phone, size: 14),
                  label: const Text('123'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.alt_route_rounded, color: Color(0xFF475569)),
                ),
                title: Text(
                  AppStrings.trafficEmergency(context),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                trailing: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.phone, size: 14),
                  label: const Text('اتصال'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCancelBookingConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.cancelBookingConfirm(context)),
        content: Text(AppStrings.cancelBookingSub(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.keepBooking(context)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final bookingId = tripData?['bookingId']?.toString();
              if (bookingId != null && bookingId.isNotEmpty) {
                try {
                  await ref.read(tripServiceProvider).cancelBooking(bookingId);
                  ref.invalidate(myBookingsProvider(false));
                  ref.invalidate(myBookingsProvider(true));
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: const Color(0xFFEF4444),
                      ),
                    );
                  }
                  return;
                }
              }
              if (context.mounted) {
                context.go('/passenger/bookings');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      AppStrings.tr(
                        context,
                        ar: 'تم إلغاء الحجز بنجاح',
                        en: 'Booking cancelled successfully',
                      ),
                    ),
                    backgroundColor: const Color(0xFFEF4444),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: Text(AppStrings.confirmCancel(context)),
          ),
        ],
      ),
    );
  }
}

