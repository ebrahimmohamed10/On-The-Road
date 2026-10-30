import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class TripDetailsScreen extends ConsumerWidget {
  final String tripId;
  final Map<String, dynamic>? tripData;

  const TripDetailsScreen({super.key, required this.tripId, this.tripData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final driverName = tripData?['driverName'] as String? ?? '';
    final carModel = tripData?['carModel'] as String? ?? '';
    final legs = List<Map<String, dynamic>>.from(
      (tripData?['legs'] as List?) ?? const [],
    );
    final fares = List<Map<String, dynamic>>.from(
      (tripData?['fares'] as List?) ?? const [],
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(AppStrings.tripDetails(context)),
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
            // مسار المحطات والتوقفات (Route Stepper)
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.routeStations(context),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (legs.isEmpty)
                    const Text('No route stops are configured for this trip.')
                  else ...[
                    Text(legs.first['from_city'] as String),
                    for (final leg in legs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_downward, size: 16),
                            const SizedBox(width: 8),
                            Expanded(child: Text(leg['to_city'] as String)),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // أسعار المقاطع المتوفرة (منطق التطبيق الرئيسي)
            Container(
              padding: const EdgeInsets.all(18),
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
                    children: [
                      const Icon(
                        Icons.calculate_rounded,
                        color: Color(0xFFF59E0B),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppStrings.tr(
                          context,
                          ar: 'أسعار المقاطع المتوفرة',
                          en: 'Segment prices',
                        ),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ...legs.map(
                    (leg) => _buildSegmentRow(
                      context,
                      '${leg['from_city']} → ${leg['to_city']}',
                      '${leg['price']}',
                    ),
                  ),
                  ...fares.map(
                    (fare) => _buildSegmentRow(
                      context,
                      '${fare['from_city']} → ${fare['to_city']} (direct fare)',
                      '${fare['price']}',
                      isFull: true,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // بيانات السائق والتقييم
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF0F172A),
                    child: Text(
                      driverName.isEmpty ? '?' : driverName.substring(0, 1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '4.9 (142 ${AppStrings.tr(context, ar: "تقييم", en: "reviews")})',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.hintColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          carModel,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () {
                      context.push('/chat/new');
                    },
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              const Expanded(
                child: Text('Fare is calculated after you choose your stops'),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    context.push(
                      '/passenger/book',
                      extra: {
                        ...?tripData,
                        'id': tripId,
                        'driverName': driverName,
                        'carModel': carModel,
                        'legs': legs,
                        'fares': fares,
                      },
                    );
                  },
                  child: Text(AppStrings.bookNow(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteStep(
    BuildContext context, {
    required String time,
    required String city,
    required String location,
    bool isStart = false,
    bool isEnd = false,
  }) {
    final theme = Theme.of(context);
    final dotColor = isStart
        ? const Color(0xFF10B981)
        : isEnd
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              time,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: theme.hintColor,
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              if (!isEnd)
                Expanded(
                  child: Container(
                    width: 2,
                    color: theme.dividerColor.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    city,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    location,
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentRow(
    BuildContext context,
    String route,
    String price, {
    bool isFull = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          route,
          style: TextStyle(
            fontWeight: isFull ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        Text(
          '$price ${AppStrings.currency(context)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isFull ? const Color(0xFFF59E0B) : null,
          ),
        ),
      ],
    );
  }
}
