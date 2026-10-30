import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_strings.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                context,
                index: 0,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: AppStrings.navHome(context),
                route: '/passenger/home',
              ),
              _buildNavItem(
                context,
                index: 1,
                icon: Icons.adjust_rounded,
                activeIcon: Icons.adjust_rounded,
                label: AppStrings.navRides(context),
                route: '/passenger/bookings',
              ),
              _buildNavItem(
                context,
                index: 2,
                icon: Icons.chat_bubble_outline_rounded,
                activeIcon: Icons.chat_bubble_rounded,
                label: AppStrings.navMessages(context),
                route: '/chat/inbox',
              ),
              _buildNavItem(
                context,
                index: 3,
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: AppStrings.navAccount(context),
                route: '/passenger/profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required String route,
  }) {
    final isSelected = currentIndex == index;
    final activeColor = const Color(0xFFF59E0B);
    final inactiveColor = const Color(0xFF94A3B8);

    return InkWell(
      onTap: () {
        if (!isSelected) {
          context.go(route);
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              size: 22,
              color: isSelected ? activeColor : inactiveColor,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
