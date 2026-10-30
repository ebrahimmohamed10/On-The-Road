import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../../../shared/widgets/app_bottom_nav.dart';

class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen> with SingleTickerProviderStateMixin {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.myTrips(context)),
        automaticallyImplyLeading: false,
        actions: const [
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
          // الرحلات القادمة
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildTripCard(
                context,
                from: 'القاهرة',
                to: 'الإسكندرية',
                date: '30 أكتوبر • 08:00 ص',
                driver: 'محمود السيد',
                car: 'تويوتا كورولا',
                seats: 2,
                price: 240,
                status: AppStrings.confirmedStatus(context),
                statusColor: const Color(0xFF10B981),
              ),
              const SizedBox(height: 14),
              _buildTripCard(
                context,
                from: 'القاهرة',
                to: 'طنطا',
                date: '02 نوفمبر • 02:30 م',
                driver: 'كريم حسني',
                car: 'هيونداي إلنترا',
                seats: 1,
                price: 60,
                status: AppStrings.pendingStatus(context),
                statusColor: const Color(0xFFF59E0B),
              ),
            ],
          ),

          // الرحلات السابقة
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildTripCard(
                context,
                from: 'الإسكندرية',
                to: 'القاهرة',
                date: '20 أكتوبر • 06:00 م',
                driver: 'محمد عادل',
                car: 'كيا سيراتو',
                seats: 1,
                price: 120,
                status: AppStrings.completedStatus(context),
                statusColor: const Color(0xFF64748B),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 1),
    );
  }

  Widget _buildTripCard(
    BuildContext context, {
    required String from,
    required String to,
    required String date,
    required String driver,
    required String car,
    required int seats,
    required int price,
    required String status,
    required Color statusColor,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$from ➔ $to',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
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
            date,
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  Text('$driver • $car', style: const TextStyle(fontSize: 12)),
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
        ],
      ),
    );
  }
}
