import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../services/trip_service.dart';

class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _cities = [];
  bool _loadingCities = true;

  Map<String, dynamic>? _originCity;
  Map<String, dynamic>? _destinationCity;
  final List<Map<String, dynamic>> _intermediateStops = [];

  DateTime _departureDate = DateTime.now().add(const Duration(hours: 3));
  TimeOfDay _departureTime = TimeOfDay.fromDateTime(
    DateTime.now().add(const Duration(hours: 3)),
  );

  int _totalSeats = 4;
  final TextEditingController _notesController = TextEditingController();
  final List<TextEditingController> _priceControllers = [];

  String? _selectedVehicleId;
  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final c in _priceControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final service = ref.read(tripServiceProvider);
    try {
      final cities = await service.getActiveCities();
      final vehicles = await service.getDriverVehicles();

      if (!mounted) return;
      setState(() {
        _cities = cities;
        _originCity = _findCity(cities, 'القاهرة', 'Cairo') ??
            (cities.isNotEmpty ? cities.first : null);
        _destinationCity = _findCity(cities, 'الإسكندرية', 'Alexandria') ??
            (cities.length > 1 ? cities[1] : null);
        if (vehicles.isNotEmpty) {
          _selectedVehicleId = vehicles.first['id']?.toString();
        }
        _loadingCities = false;
        _recalculatePriceFields();
      });
    } catch (_) {
      if (mounted) setState(() => _loadingCities = false);
    }
  }

  Map<String, dynamic>? _findCity(
    List<Map<String, dynamic>> list,
    String ar,
    String en,
  ) {
    for (final c in list) {
      if (c['name_ar'] == ar || c['name_en'] == en) return c;
    }
    return null;
  }

  String _cityLabel(Map<String, dynamic>? city) {
    if (city == null) return '';
    final isAr = AppStrings.isArabic(context);
    return (isAr
            ? city['name_ar'] ?? city['name_en']
            : city['name_en'] ?? city['name_ar'])
        .toString();
  }

  void _recalculatePriceFields() {
    final routeLength = 2 + _intermediateStops.length;
    final legCount = routeLength - 1;

    while (_priceControllers.length < legCount) {
      _priceControllers.add(TextEditingController(text: '150'));
    }
    while (_priceControllers.length > legCount) {
      _priceControllers.removeLast().dispose();
    }
  }

  List<Map<String, dynamic>> get _allRouteStops {
    final list = <Map<String, dynamic>>[];
    if (_originCity != null) list.add(_originCity!);
    list.addAll(_intermediateStops);
    if (_destinationCity != null) list.add(_destinationCity!);
    return list;
  }

  Future<void> _pickDepartureDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _departureDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _departureDate = picked);
    }
  }

  Future<void> _pickDepartureTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _departureTime,
    );
    if (picked != null) {
      setState(() => _departureTime = picked);
    }
  }

  Future<void> _publishTrip() async {
    if (_originCity == null || _destinationCity == null) return;
    if (_originCity!['id'] == _destinationCity!['id']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.tr(
              context,
              ar: 'مدينة الانطلاق ومدينة الوصول يجب أن تكونا مختلفتين.',
              en: 'Origin and destination cities must be different.',
            ),
          ),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    final fullDeparture = DateTime(
      _departureDate.year,
      _departureDate.month,
      _departureDate.day,
      _departureTime.hour,
      _departureTime.minute,
    );

    // Approximate arrival: 2.5 hours + 45 mins per intermediate stop
    final arrivalTime = fullDeparture.add(
      Duration(minutes: 150 + (_intermediateStops.length * 45)),
    );

    final legPrices = _priceControllers
        .map((c) => int.tryParse(c.text.trim()) ?? 150)
        .toList();

    final cityIds = _allRouteStops.map((c) => c['id'].toString()).toList();
    final cityNames = _allRouteStops.map((c) => _cityLabel(c)).toList();

    setState(() => _isPublishing = true);

    try {
      await ref.read(tripServiceProvider).createAndPublishTrip(
            vehicleId: _selectedVehicleId,
            cityIds: cityIds,
            cityNames: cityNames,
            departureTime: fullDeparture,
            arrivalTime: arrivalTime,
            totalSeats: _totalSeats,
            legPrices: legPrices,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      ref.invalidate(driverTripsProvider);
      ref.invalidate(driverPendingBookingsProvider);

      if (!mounted) return;
      setState(() => _isPublishing = false);

      context.go('/driver/home');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.tr(
              context,
              ar: 'تم نشر الرحلة بنجاح! جاهزة لاستقبال الحجوزات.',
              en: 'Ride published successfully! Ready for bookings.',
            ),
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.publishNewTrip(context)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
      ),
      body: _loadingCities
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ─── Section 1: Route Planner ─────────────────────
                    _buildSectionCard(
                      theme: theme,
                      title: AppStrings.routeStops(context),
                      icon: Icons.alt_route_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Origin City
                          _buildCityPickerField(
                            label: AppStrings.fromCity(context),
                            selectedCity: _originCity,
                            icon: Icons.trip_origin_rounded,
                            iconColor: const Color(0xFF10B981),
                            onSelected: (city) {
                              setState(() {
                                _originCity = city;
                                _recalculatePriceFields();
                              });
                            },
                          ),

                          const SizedBox(height: 12),

                          // Intermediate Stops
                          for (int i = 0; i < _intermediateStops.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _buildCityPickerField(
                                      label: '${AppStrings.tr(context, ar: "محطة توقف", en: "Stop")} ${i + 1}',
                                      selectedCity: _intermediateStops[i],
                                      icon: Icons.add_location_alt_outlined,
                                      iconColor: const Color(0xFFF59E0B),
                                      onSelected: (city) {
                                        setState(() {
                                          _intermediateStops[i] = city;
                                          _recalculatePriceFields();
                                        });
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444)),
                                    onPressed: () {
                                      setState(() {
                                        _intermediateStops.removeAt(i);
                                        _recalculatePriceFields();
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],

                          if (_intermediateStops.length < 3)
                            TextButton.icon(
                              onPressed: () {
                                final remaining = _cities.where((c) =>
                                    c['id'] != _originCity?['id'] &&
                                    c['id'] != _destinationCity?['id'] &&
                                    !_intermediateStops.any((s) => s['id'] == c['id'])).toList();
                                if (remaining.isNotEmpty) {
                                  setState(() {
                                    _intermediateStops.add(remaining.first);
                                    _recalculatePriceFields();
                                  });
                                }
                              },
                              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                              label: Text(
                                AppStrings.tr(context, ar: '+ إضافة محطة مرور على الطريق', en: '+ Add waypoint stop'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFFF59E0B),
                              ),
                            ),

                          const SizedBox(height: 6),

                          // Destination City
                          _buildCityPickerField(
                            label: AppStrings.toCity(context),
                            selectedCity: _destinationCity,
                            icon: Icons.location_on_rounded,
                            iconColor: const Color(0xFFEF4444),
                            onSelected: (city) {
                              setState(() {
                                _destinationCity = city;
                                _recalculatePriceFields();
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ─── Section 2: Date & Time ───────────────────────
                    _buildSectionCard(
                      theme: theme,
                      title: AppStrings.departureTimeLabel(context),
                      icon: Icons.access_time_rounded,
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickDepartureDate,
                              icon: const Icon(Icons.calendar_today_rounded, size: 18),
                              label: Text(
                                '${_departureDate.day}/${_departureDate.month}/${_departureDate.year}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickDepartureTime,
                              icon: const Icon(Icons.schedule_rounded, size: 18),
                              label: Text(
                                _departureTime.format(context),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ─── Section 3: Available Seats ───────────────────
                    _buildSectionCard(
                      theme: theme,
                      title: AppStrings.availableSeatsLabel(context),
                      icon: Icons.airline_seat_recline_extra_rounded,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            AppStrings.tr(
                              context,
                              ar: 'عدد المقاعد المعروضة للحجز',
                              en: 'Number of offered seats',
                            ),
                            style: TextStyle(fontSize: 13, color: theme.hintColor),
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: _totalSeats > 1
                                    ? () => setState(() => _totalSeats--)
                                    : null,
                                icon: const Icon(Icons.remove_circle_outline_rounded),
                              ),
                              Text(
                                '$_totalSeats',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                              IconButton(
                                onPressed: _totalSeats < 6
                                    ? () => setState(() => _totalSeats++)
                                    : null,
                                icon: const Icon(Icons.add_circle_outline_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ─── Section 4: Segment Prices ────────────────────
                    _buildSectionCard(
                      theme: theme,
                      title: AppStrings.tr(context, ar: 'أسعار المقاطع (جنيه)', en: 'Segment Fares (EGP)'),
                      icon: Icons.payments_outlined,
                      child: Column(
                        children: [
                          for (int i = 0; i < _priceControllers.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_cityLabel(_allRouteStops[i])} ➔ ${_cityLabel(_allRouteStops[i + 1])}',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 100,
                                    child: TextField(
                                      controller: _priceControllers[i],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                        suffixText: AppStrings.currency(context),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ─── Section 5: Notes & Rules ─────────────────────
                    _buildSectionCard(
                      theme: theme,
                      title: AppStrings.tripNotesLabel(context),
                      icon: Icons.notes_rounded,
                      child: TextField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: AppStrings.tr(
                            context,
                            ar: 'مثال: سيارة مكيفة، ممنوع التدخين، حقيبة واحدة متوسطة لكل راكب...',
                            en: 'e.g. AC car, no smoking, 1 medium bag per rider...',
                          ),
                          hintStyle: TextStyle(fontSize: 12, color: theme.hintColor),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ─── Submit Button ────────────────────────────────
                    ElevatedButton(
                      onPressed: _isPublishing ? null : _publishTrip,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isPublishing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              AppStrings.publishTripAction(context),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionCard({
    required ThemeData theme,
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.12)),
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
              Icon(icon, size: 18, color: const Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildCityPickerField({
    required String label,
    required Map<String, dynamic>? selectedCity,
    required IconData icon,
    required Color iconColor,
    required ValueChanged<Map<String, dynamic>> onSelected,
  }) {
    return InkWell(
      onTap: () => _showCityPicker(label, onSelected),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
                  ),
                  Text(
                    _cityLabel(selectedCity),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  void _showCityPicker(
    String title,
    ValueChanged<Map<String, dynamic>> onSelected,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _cities.length,
                itemBuilder: (ctx, index) {
                  final city = _cities[index];
                  return ListTile(
                    title: Text(_cityLabel(city)),
                    onTap: () {
                      onSelected(city);
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
