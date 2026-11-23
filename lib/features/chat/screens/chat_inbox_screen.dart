import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../services/chat_service.dart';

class ChatInboxScreen extends ConsumerStatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  ConsumerState<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends ConsumerState<ChatInboxScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTime(BuildContext context, dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString()).toLocal();
      final now = DateTime.now();
      final isAr = AppStrings.isArabic(context);

      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final isYesterday = dt.year == now.year && dt.month == now.month && dt.day == now.day - 1;

      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final period = isAr ? (dt.hour >= 12 ? 'م' : 'ص') : (dt.hour >= 12 ? 'PM' : 'AM');
      final minute = dt.minute.toString().padLeft(2, '0');
      final timeStr = '$hour:$minute $period';

      if (isToday) return timeStr;
      if (isYesterday) return isAr ? 'أمس' : 'Yesterday';

      final arMonths = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
      ];
      final enMonths = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final monthName = isAr ? arMonths[dt.month - 1] : enMonths[dt.month - 1];
      return '${dt.day} $monthName';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final convAsync = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.chatInboxTitle(context)),
        automaticallyImplyLeading: false,
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── Search Bar ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: AppStrings.searchConversations(context),
                hintStyle: TextStyle(fontSize: 13, color: theme.hintColor),
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xFFF59E0B),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // ─── Conversations List ─────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(conversationsProvider);
              },
              child: convAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 40, color: Color(0xFFEF4444)),
                        const SizedBox(height: 12),
                        Text(
                          err.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.hintColor, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => ref.invalidate(conversationsProvider),
                          child: Text(AppStrings.tr(context, ar: 'إعادة المحاولة', en: 'Retry')),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (conversations) {
                  // Filter according to search query
                  final filtered = conversations.where((conv) {
                    if (_searchQuery.isEmpty) return true;
                    final driver = conv['driver'] as Map<String, dynamic>? ?? {};
                    final rider = conv['rider'] as Map<String, dynamic>? ?? {};
                    final trip = conv['trip'] as Map<String, dynamic>? ?? {};
                    final driverName = (driver['name'] ?? '').toString().toLowerCase();
                    final riderName = (rider['name'] ?? '').toString().toLowerCase();
                    final from = (trip['origin_city'] ?? '').toString().toLowerCase();
                    final to = (trip['destination_city'] ?? '').toString().toLowerCase();
                    return driverName.contains(_searchQuery) ||
                        riderName.contains(_searchQuery) ||
                        from.contains(_searchQuery) ||
                        to.contains(_searchQuery);
                  }).toList();

                  if (filtered.isEmpty) {
                    return _buildEmptyState(context, theme);
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final conv = filtered[index];
                      return _buildConversationCard(context, conv, theme, isDark);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
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
            Icons.chat_bubble_outline_rounded,
            size: 44,
            color: Color(0xFFF59E0B),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppStrings.noConversationsTitle(context),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.noConversationsSubtitle(context),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: theme.hintColor,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: ElevatedButton.icon(
            onPressed: () => context.go('/passenger/search'),
            icon: const Icon(Icons.search_rounded),
            label: Text(AppStrings.searchRidesBtn(context)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConversationCard(
    BuildContext context,
    Map<String, dynamic> conv,
    ThemeData theme,
    bool isDark,
  ) {
    final user = ref.read(chatServiceProvider).currentUser;
    final driver = conv['driver'] as Map<String, dynamic>? ?? {};
    final rider = conv['rider'] as Map<String, dynamic>? ?? {};
    final trip = conv['trip'] as Map<String, dynamic>? ?? {};
    final booking = conv['booking'] as Map<String, dynamic>? ?? {};
    final lastMsg = conv['last_message'] as Map<String, dynamic>?;

    final isDriver = user != null && user.id == conv['driver_id'];
    final otherParty = isDriver ? rider : driver;
    final name = otherParty['name']?.toString() ??
        (isDriver ? (AppStrings.isArabic(context) ? 'الراكب' : 'Passenger') : (AppStrings.isArabic(context) ? 'السائق' : 'Driver'));
    final phone = otherParty['phone']?.toString();
    final initials = name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join();

    final fromCity = booking['pickup_city']?.toString() ?? trip['origin_city']?.toString() ?? '';
    final toCity = booking['dropoff_city']?.toString() ?? trip['destination_city']?.toString() ?? '';
    final routeStr = fromCity.isNotEmpty && toCity.isNotEmpty ? '$fromCity ➔ $toCity' : '';

    final bookingId = conv['booking_id']?.toString() ?? '';
    final lastMsgContent = lastMsg?['content']?.toString() ??
        AppStrings.tr(context, ar: 'المحادثة جاهزة للتنسيق', en: 'Conversation ready to coordinate');
    final timeStr = _formatTime(context, lastMsg?['created_at'] ?? conv['updated_at']);

    return InkWell(
      onTap: () {
        context.push('/chat/$bookingId', extra: {
          'bookingId': bookingId,
          'driverName': name,
          'driverInitials': initials,
          'phone': phone,
          'route': routeStr,
          'carModel': driver['car_model'],
          'bookingStatus': booking['status'],
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.15),
              child: Text(
                initials.isEmpty ? '?' : initials,
                style: const TextStyle(
                  color: Color(0xFFD97706),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.hintColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (routeStr.isNotEmpty)
                    Text(
                      routeStr,
                      style: TextStyle(
                        fontSize: 11,
                        color: const Color(0xFFF59E0B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    lastMsgContent,
                    style: TextStyle(
                      fontSize: 13,
                      color: lastMsg != null ? theme.textTheme.bodyMedium?.color : theme.hintColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
