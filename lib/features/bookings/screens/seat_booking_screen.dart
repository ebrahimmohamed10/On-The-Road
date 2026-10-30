import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';

class SeatBookingScreen extends StatefulWidget {
  final Map<String, dynamic>? bookingData;
  const SeatBookingScreen({super.key, this.bookingData});

  @override
  State<SeatBookingScreen> createState() => _SeatBookingScreenState();
}

class _SeatBookingScreenState extends State<SeatBookingScreen> {
  String? _pickupCity;
  String? _dropoffCity;
  int _seatCount = 0;

  List<String> get _stops {
    final legs = (widget.bookingData?['legs'] as List?) ?? const [];
    if (legs.isNotEmpty) {
      final ordered =
          List<Map<String, dynamic>>.from(
            legs.map((leg) => Map<String, dynamic>.from(leg)),
          )..sort(
            (a, b) => (a['segment_order'] as num).compareTo(
              b['segment_order'] as num,
            ),
          );
      return [
        ordered.first['from_city'] as String,
        ...ordered.map((leg) => leg['to_city'] as String),
      ];
    }
    return List<String>.from(
      (widget.bookingData?['waypoints'] as List?) ?? const [],
    );
  }

  int get _seatCapacity =>
      (widget.bookingData?['total_seats'] as num?)?.toInt() ?? 0;

  bool get _canContinue =>
      widget.bookingData?['id'] != null &&
      _pickupCity != null &&
      _dropoffCity != null &&
      _stops.indexOf(_pickupCity!) < _stops.indexOf(_dropoffCity!) &&
      _seatCount > 0;

  void _continue() {
    if (!_canContinue) return;
    context.push(
      '/passenger/payment',
      extra: {
        'tripId': widget.bookingData!['id'].toString(),
        'pickupCity': _pickupCity,
        'dropoffCity': _dropoffCity,
        'seatsCount': _seatCount,
        'driverName': widget.bookingData?['driverName'] ?? '',
        'departureTime': widget.bookingData?['departure_time'],
        'legs': widget.bookingData?['legs'],
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stops = _stops;
    final hasTrip = widget.bookingData?['id'] != null && stops.length >= 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.confirmBooking(context)),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
      ),
      body: !hasTrip
          ? const Center(
              child: Text(
                'Trip route data is unavailable. Please return to search.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Choose your route', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _pickupCity,
                  decoration: const InputDecoration(labelText: 'Pickup stop'),
                  items: stops
                      .take(stops.length - 1)
                      .map(
                        (city) =>
                            DropdownMenuItem(value: city, child: Text(city)),
                      )
                      .toList(),
                  onChanged: (city) => setState(() {
                    _pickupCity = city;
                    if (city != null &&
                        _dropoffCity != null &&
                        stops.indexOf(_dropoffCity!) <= stops.indexOf(city)) {
                      _dropoffCity = null;
                    }
                  }),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _dropoffCity,
                  decoration: const InputDecoration(labelText: 'Drop-off stop'),
                  items: stops
                      .where(
                        (city) =>
                            _pickupCity == null ||
                            stops.indexOf(city) > stops.indexOf(_pickupCity!),
                      )
                      .map(
                        (city) =>
                            DropdownMenuItem(value: city, child: Text(city)),
                      )
                      .toList(),
                  onChanged: (city) => setState(() => _dropoffCity = city),
                ),
                const SizedBox(height: 28),
                Text('Number of seats', style: theme.textTheme.titleMedium),
                Row(
                  children: [
                    IconButton(
                      onPressed: _seatCount > 0
                          ? () => setState(() => _seatCount--)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$_seatCount', style: theme.textTheme.titleLarge),
                    IconButton(
                      onPressed: _seatCount < _seatCapacity
                          ? () => setState(() => _seatCount++)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    Text('of $_seatCapacity seats available on this trip'),
                  ],
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _canContinue ? _continue : null,
                  child: Text(AppStrings.proceedToPayment(context)),
                ),
              ],
            ),
    );
  }
}
