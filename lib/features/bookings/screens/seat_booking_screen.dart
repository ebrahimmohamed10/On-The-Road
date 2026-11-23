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
  int _seatCount = 1;

  @override
  void initState() {
    super.initState();
    final requestedSeats = (widget.bookingData?['seats'] as num?)?.toInt() ??
        (widget.bookingData?['seatsCount'] as num?)?.toInt() ??
        1;
    _seatCount = requestedSeats > 0 ? requestedSeats : 1;

    final stops = _stops;
    final from = widget.bookingData?['from']?.toString();
    final to = widget.bookingData?['to']?.toString();
    if (from != null && stops.contains(from)) {
      _pickupCity = from;
    }
    if (to != null && stops.contains(to)) {
      if (_pickupCity == null || stops.indexOf(to) > stops.indexOf(_pickupCity!)) {
        _dropoffCity = to;
      }
    }
  }

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

  int get _seatCapacity {
    final available = (widget.bookingData?['availableSeats'] as num?)?.toInt();
    if (available != null && available > 0) return available;
    final total = (widget.bookingData?['total_seats'] as num?)?.toInt();
    if (total != null && total > 0) return total;
    return 4;
  }

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
        'departureTime': widget.bookingData?['departureTime'] ?? widget.bookingData?['departure_time'],
        'legs': widget.bookingData?['legs'],
        'searchPriceMinor': widget.bookingData?['searchPriceMinor'],
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
          ? Center(
              child: Text(
                AppStrings.tr(
                  context,
                  ar: 'بيانات مسار الرحلة غير متوفرة. يرجى العودة للبحث.',
                  en: 'Trip route data is unavailable. Please return to search.',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  AppStrings.tr(
                    context,
                    ar: 'اختر خط سيرك',
                    en: 'Choose your route',
                  ),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _pickupCity,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr(
                      context,
                      ar: 'نقطة الركوب',
                      en: 'Pickup stop',
                    ),
                  ),
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
                  initialValue: _dropoffCity,
                  decoration: InputDecoration(
                    labelText: AppStrings.tr(
                      context,
                      ar: 'نقطة النزول',
                      en: 'Drop-off stop',
                    ),
                  ),
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
                Text(
                  AppStrings.tr(
                    context,
                    ar: 'عدد المقاعد',
                    en: 'Number of seats',
                  ),
                  style: theme.textTheme.titleMedium,
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: _seatCount > 1
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
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.tr(
                        context,
                        ar: 'من أصل $_seatCapacity مقاعد متاحة',
                        en: 'of $_seatCapacity seats available',
                      ),
                    ),
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
