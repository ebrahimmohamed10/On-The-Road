import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../services/trip_service.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen>
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

  Color _tripStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'published':
        return const Color(0xFF10B981);
      case 'in_progress':
        return const Color(0xFFF59E0B);
      case 'completed':
        return const Color(0xFF64748B);
      case 'cancelled':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF10B981);
    }
  }

  String _tripStatusLabel(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'published':
        return AppStrings.tr(context, ar: 'منشورة وجاهزة', en: 'Published');
      case 'in_progress':
        return AppStrings.tr(context, ar: 'جارية على الطريق 🚗', en: 'In progress 🚗');
      case 'completed':
        return AppStrings.tr(context, ar: 'مكتملة 🏁', en: 'Completed 🏁');
      case 'cancelled':
        return AppStrings.tr(context, ar: 'ملغاة', en: 'Cancelled');
      default:
        return status;
    }
  }

  Future<void> _handleStartTrip(String tripId) async {
    try {
      await ref.read(tripServiceProvider).startTrip(tripId);
      ref.invalidate(driverTripsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.tripStartedSuccess(context)),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _handleCompleteTrip(String tripId) async {
    try {
      await ref.read(tripServiceProvider).completeTrip(tripId);
      ref.invalidate(driverTripsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.tripCompletedSuccess(context)),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  Future<void> _handleBookingResponse(String bookingId, bool accept) async {
    try {
      await ref.read(tripServiceProvider).respondToBooking(
            bookingId: bookingId,
            accept: accept,
          );
      ref.invalidate(driverPendingBookingsProvider);
      ref.invalidate(driverTripsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? AppStrings.bookingAcceptedSuccess(context)
                : AppStrings.bookingRejectedSuccess(context),
          ),
          backgroundColor: accept ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: const Color(0xFFEF4444)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final tripsAsync = ref.watch(driverTripsProvider);
    final requestsAsync = ref.watch(driverPendingBookingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'DRIVER',
                style: TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(AppStrings.driverDashboard(context)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/passenger/home'),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: Text(
              AppStrings.tr(context, ar: 'وضع الراكب', en: 'Passenger Mode'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFF59E0B)),
          ),
          const Padding(
            padding: EdgeInsetsDirectional.only(end: 12),
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
            Tab(text: AppStrings.myDriverTrips(context)),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(AppStrings.bookingRequests(context)),
                  const SizedBox(width: 6),
                  requestsAsync.maybeWhen(
                    data: (reqs) => reqs.isNotEmpty
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${reqs.length}',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          )
                        : const SizedBox.shrink(),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ─── Tab 1: Trips List ──────────────────────────────
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(driverTripsProvider);
            },
            child: tripsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text(err.toString())),
              data: (trips) {
                if (trips.isEmpty) {
                  return _buildEmptyTripsState(context, theme);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: trips.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final trip = trips[index];
                    return _buildDriverTripCard(context, trip, theme, isDark);
                  },
                );
              },
            ),
          ),

          // ─── Tab 2: Pending Requests ────────────────────────
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(driverPendingBookingsProvider);
            },
            child: requestsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text(err.toString())),
              data: (requests) {
                if (requests.isEmpty) {
                  return _buildEmptyRequestsState(context, theme);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: requests.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    return _buildBookingRequestCard(context, req, theme, isDark);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/driver/create-trip'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: const Color(0xFFF59E0B),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          AppStrings.publishNewTrip(context),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildEmptyTripsState(BuildContext context, ThemeData theme) {
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
            Icons.directions_car_filled_outlined,
            size: 44,
            color: Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppStrings.noDriverTrips(context),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.noDriverTripsSub(context),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: theme.hintColor, height: 1.5),
        ),
        const SizedBox(height: 28),
        Center(
          child: ElevatedButton.icon(
            onPressed: () => context.push('/driver/create-trip'),
            icon: const Icon(Icons.add_rounded),
            label: Text(AppStrings.publishNewTrip(context)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyRequestsState(BuildContext context, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.done_all_rounded,
            size: 44,
            color: Color(0xFF10B981),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppStrings.noPendingRequests(context),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.tr(
            context,
            ar: 'عندما يقوم الركاب بطلب مقاعد على رحلاتك ستظهر طلباتهم هنا للموافقة عليها.',
            en: 'When riders request seats on your trips, they will appear here for your approval.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: theme.hintColor, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildDriverTripCard(
    BuildContext context,
    Map<String, dynamic> trip,
    ThemeData theme,
    bool isDark,
  ) {
    final tripId = trip['id']?.toString() ?? '';
    final origin = trip['origin_city']?.toString() ?? '';
    final dest = trip['destination_city']?.toString() ?? '';
    final departureStr = _formatDateTime(context, trip['departure_time']);
    final status = trip['status']?.toString() ?? 'published';
    final totalSeats = (trip['total_seats'] as num?)?.toInt() ?? 4;

    final bookings = List<Map<String, dynamic>>.from(
      (trip['bookings'] as List?) ?? const [],
    );

    final confirmedBookings = bookings.where((b) => b['status'] == 'confirmed').toList();
    final bookedSeatsCount = confirmedBookings.fold<int>(
      0,
      (sum, b) => sum + ((b['seats_booked'] as num?)?.toInt() ?? 1),
    );

    final statusColor = _tripStatusColor(status);
    final statusLabel = _tripStatusLabel(context, status);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '$origin ➔ $dest',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
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
                  departureStr,
                  style: TextStyle(fontSize: 12, color: theme.hintColor),
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.airline_seat_recline_extra_rounded,
                          size: 16,
                          color: Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          AppStrings.tr(
                            context,
                            ar: '$bookedSeatsCount / $totalSeats مقاعد محجوزة',
                            en: '$bookedSeatsCount / $totalSeats seats booked',
                          ),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      AppStrings.tr(
                        context,
                        ar: '${confirmedBookings.length} ركاب مؤكدين',
                        en: '${confirmedBookings.length} riders confirmed',
                      ),
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Trip Control Buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (status == 'published') ...[
                  ElevatedButton.icon(
                    onPressed: () => _handleStartTrip(tripId),
                    icon: const Icon(Icons.play_arrow_rounded, size: 16),
                    label: Text(AppStrings.startTripBtn(context)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ] else if (status == 'in_progress') ...[
                  ElevatedButton.icon(
                    onPressed: () => _handleCompleteTrip(tripId),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: Text(AppStrings.completeTripBtn(context)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ] else ...[
                  Text(
                    AppStrings.tr(context, ar: 'تم انتهاء الرحلة', en: 'Trip ended'),
                    style: TextStyle(color: theme.hintColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],

                if (confirmedBookings.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _showRidersSheet(context, origin, dest, confirmedBookings),
                    icon: const Icon(Icons.people_alt_outlined, size: 16),
                    label: Text(AppStrings.tr(context, ar: 'قائمة الركاب', en: 'Riders list')),
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFF59E0B)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingRequestCard(
    BuildContext context,
    Map<String, dynamic> req,
    ThemeData theme,
    bool isDark,
  ) {
    final bookingId = req['id']?.toString() ?? '';
    final passenger = req['passenger'] as Map<String, dynamic>? ?? {};
    final passengerName = passenger['name']?.toString() ??
        (AppStrings.isArabic(context) ? 'مسافر' : 'Passenger');
    final passengerRating = (passenger['rating'] as num?)?.toDouble() ?? 5.0;
    final phone = passenger['phone']?.toString();
    final pickup = req['pickup_city']?.toString() ?? '';
    final dropoff = req['dropoff_city']?.toString() ?? '';
    final seats = (req['seats_booked'] as num?)?.toInt() ?? 1;

    final rawPrice = req['total_price'];
    final price = rawPrice is num
        ? (rawPrice > 1000 ? (rawPrice / 100).round() : rawPrice.round())
        : 150;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                child: Text(
                  passengerName.isNotEmpty ? passengerName.substring(0, 1) : '?',
                  style: const TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      passengerName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          '$passengerRating',
                          style: TextStyle(fontSize: 12, color: theme.hintColor, fontWeight: FontWeight.bold),
                        ),
                        if (phone != null) ...[
                          const SizedBox(width: 8),
                          Text('• $phone', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFF59E0B), size: 20),
                onPressed: () {
                  context.push('/chat/$bookingId', extra: {
                    'bookingId': bookingId,
                    'driverName': passengerName,
                    'route': '$pickup ➔ $dropoff',
                  });
                },
              ),
            ],
          ),

          const Divider(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$pickup ➔ $dropoff',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    AppStrings.tr(
                      context,
                      ar: '$seats مقاعد مطلوبة',
                      en: '$seats seats requested',
                    ),
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
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

          const SizedBox(height: 16),

          // Accept & Reject Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleBookingResponse(bookingId, false),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    foregroundColor: const Color(0xFFEF4444),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    AppStrings.rejectBooking(context),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleBookingResponse(bookingId, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    AppStrings.acceptBooking(context),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showRidersSheet(
    BuildContext context,
    String origin,
    String dest,
    List<Map<String, dynamic>> bookings,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.tr(context, ar: 'ركاب الرحلة ($origin ➔ $dest)', en: 'Riders on trip ($origin ➔ $dest)'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Divider(height: 24),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: bookings.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (ctx, idx) {
                    final b = bookings[idx];
                    final p = b['passenger'] as Map<String, dynamic>? ?? {};
                    final name = p['name']?.toString() ?? 'راكب';
                    final phone = p['phone']?.toString() ?? '';
                    final seats = b['seats_booked'] ?? 1;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.15),
                        child: Text(
                          name.isNotEmpty ? name.substring(0, 1) : '?',
                          style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold),
                        ),
                      ),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '${b['pickup_city']} ➔ ${b['dropoff_city']} • $seats ${AppStrings.tr(context, ar: "مقاعد", en: "seats")}\n$phone',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFFF59E0B)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          context.push('/chat/${b['id']}', extra: {
                            'bookingId': b['id'],
                            'driverName': name,
                            'route': '${b['pickup_city']} ➔ ${b['dropoff_city']}',
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
