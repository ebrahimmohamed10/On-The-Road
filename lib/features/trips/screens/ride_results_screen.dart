import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../services/trip_service.dart';

class RideResultsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? searchParams;
  const RideResultsScreen({super.key, this.searchParams});

  @override
  ConsumerState<RideResultsScreen> createState() => _RideResultsScreenState();
}

class _RideResultsScreenState extends ConsumerState<RideResultsScreen> {
  int _selectedFilter = 0;
  List<Map<String, dynamic>> _liveTrips = [];
  bool _isLoading = true;

  final List<Map<String, dynamic>> _fallbackTrips = [
    {
      'id': 'trip-1',
      'driverName': 'محمود السيد',
      'driverRating': 4.9,
      'tripsCount': 142,
      'carModel': 'تويوتا كورولا 2022',
      'departureTime': '08:00 ص',
      'arrivalTime': '10:30 ص',
      'availableSeats': 3,
      'price': 120,
      'waypoints': ['القاهرة', 'طنطا', 'الإسكندرية'],
    },
    {
      'id': 'trip-2',
      'driverName': 'كريم حسني',
      'driverRating': 4.8,
      'tripsCount': 89,
      'carModel': 'هيونداي إلنترا 2023',
      'departureTime': '09:30 ص',
      'arrivalTime': '12:00 م',
      'availableSeats': 1,
      'price': 110,
      'waypoints': ['القاهرة', 'بنها', 'دمنهور', 'الإسكندرية'],
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchLiveTrips();
  }

  Future<void> _fetchLiveTrips() async {
    final fromCity = widget.searchParams?['from'] as String?;
    final toCity = widget.searchParams?['to'] as String?;

    final service = ref.read(tripServiceProvider);
    final results = await service.getTrips(fromCity: fromCity, toCity: toCity);

    if (mounted) {
      setState(() {
        if (results.isNotEmpty) {
          _liveTrips = results.map((t) {
            final driver = t['driver'] as Map<String, dynamic>?;
            final segments = (t['segments'] as List?) ?? [];
            final price = segments.isNotEmpty
                ? (segments.last['price'] as num).toInt()
                : 120;

            return {
              'id': t['id'].toString(),
              'driverName': driver?['name'] ?? 'سائق على الطريق',
              'driverRating': (driver?['rating'] as num?)?.toDouble() ?? 5.0,
              'tripsCount': driver?['trips_count'] ?? 10,
              'carModel': driver?['car_model'] ?? 'سيارة خاصة',
              'departureTime': '08:00 ص',
              'arrivalTime': '10:30 ص',
              'availableSeats': t['total_seats'] ?? 3,
              'price': price,
              'waypoints': [t['origin_city'], ...segments.map((s) => s['to_city'])],
            };
          }).toList();
        } else {
          _liveTrips = _fallbackTrips;
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromCity = widget.searchParams?['from'] ?? 'القاهرة';
    final toCity = widget.searchParams?['to'] ?? 'الإسكندرية';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: Text(
          '$fromCity ➔ $toCity',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
      ),
      body: Column(
        children: [
          // فلاتر الترتيب
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip(0, AppStrings.tr(context, ar: 'الأعلى تقييماً', en: 'Top rated')),
                const SizedBox(width: 8),
                _buildFilterChip(1, AppStrings.tr(context, ar: 'الأرخص سعراً', en: 'Cheapest')),
                const SizedBox(width: 8),
                _buildFilterChip(2, AppStrings.tr(context, ar: 'الأبكر موعداً', en: 'Earliest')),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // قائمة الرحلات
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchLiveTrips,
                    color: const Color(0xFFF59E0B),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _liveTrips.length,
                      itemBuilder: (context, index) {
                        final trip = _liveTrips[index];
                        return _buildTripCard(trip, theme);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedFilter == index;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = index),
      selectedColor: const Color(0xFFF59E0B),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : null,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  Widget _buildTripCard(Map<String, dynamic> trip, ThemeData theme) {
    final waypoints = (trip['waypoints'] as List).join(' ➔ ');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          context.push('/passenger/trip/${trip['id']}', extra: trip);
        },
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        trip['departureTime'],
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 16, color: theme.hintColor),
                      const SizedBox(width: 8),
                      Text(
                        trip['arrivalTime'],
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${trip['price']}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        AppStrings.currency(context),
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.hintColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.route_rounded, size: 16, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      waypoints,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF0F172A),
                        child: Text(
                          trip['driverName'].toString().substring(0, 1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trip['driverName'],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                              const SizedBox(width: 2),
                              Text(
                                '${trip['driverRating']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.hintColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '• ${trip['carModel']}',
                                style: TextStyle(fontSize: 11, color: theme.hintColor),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.airline_seat_recline_extra_rounded,
                          size: 14,
                          color: Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppStrings.availableSeats(context, trip['availableSeats']),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
