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

    if (!mounted) return;
    setState(() {
      _liveTrips = results.map((trip) {
        final driver = trip['driver'] as Map<String, dynamic>?;
        final segments = List<Map<String, dynamic>>.from(
          ((trip['segments'] as List?) ?? []).map(
            (segment) => Map<String, dynamic>.from(segment),
          ),
        )..sort(
          (a, b) => (a['segment_order'] as num).compareTo(
            b['segment_order'] as num,
          ),
        );
        final legs = segments
            .where((segment) => segment['segment_kind'] == 'leg')
            .toList();
        return {
          ...trip,
          'id': trip['id'].toString(),
          'driverName': driver?['name'] ?? '',
          'driverRating': (driver?['rating'] as num?)?.toDouble() ?? 0,
          'tripsCount': driver?['trips_count'] ?? 0,
          'carModel': driver?['car_model'] ?? '',
          'availableSeats': trip['total_seats'],
          'departureTime': trip['departure_time']?.toString() ?? '',
          'arrivalTime': trip['arrival_time']?.toString() ?? '',
          'segments': segments,
          'legs': legs,
          'fares': segments
              .where((segment) => segment['segment_kind'] == 'fare_override')
              .toList(),
          'waypoints': [
            if (legs.isNotEmpty) legs.first['from_city'],
            ...legs.map((segment) => segment['to_city']),
          ],
        };
      }).toList();
      _isLoading = false;
    });
  }
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromCity = widget.searchParams?['from'] ?? '';
    final toCity = widget.searchParams?['to'] ?? '';

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
                : _liveTrips.isEmpty
                    ? const Center(child: Text('No trips were found.'))
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
                  const Text(
                    'Choose stops to see fare',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),              const SizedBox(height: 8),
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
                          trip['driverName'].toString().isEmpty ? '?' : trip['driverName'].toString().substring(0, 1),
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
                          'Capacity: ${trip["availableSeats"]}',
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
