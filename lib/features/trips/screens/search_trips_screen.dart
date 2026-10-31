import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/language_theme_actions.dart';
import '../services/trip_service.dart';

class SearchTripsScreen extends ConsumerStatefulWidget {
  const SearchTripsScreen({super.key});

  @override
  ConsumerState<SearchTripsScreen> createState() => _SearchTripsScreenState();
}

class _SearchTripsScreenState extends ConsumerState<SearchTripsScreen> {
  DateTime _selectedDate = DateTime.now();
  int _seatsCount = 1;
  List<Map<String, dynamic>> _cities = [];
  Map<String, dynamic>? _fromCity;
  Map<String, dynamic>? _toCity;
  bool _loadingCities = true;
  String? _cityLoadError;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  Future<void> _loadCities() async {
    try {
      final cities = await ref.read(tripServiceProvider).getActiveCities();
      if (!mounted) return;
      setState(() {
        _cities = cities;
        _fromCity =
            _findCityByLabel(cities, 'القاهرة', 'Cairo') ??
            (cities.isNotEmpty ? cities.first : null);
        _toCity =
            _findCityByLabel(cities, 'الإسكندرية', 'Alexandria') ??
            (cities.length > 1 ? cities[1] : null);
        _loadingCities = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCities = false;
        _cityLoadError = AppStrings.tr(
          context,
          ar: 'تعذر تحميل المدن المعتمدة. تحقق من الاتصال وحاول مجددًا.',
          en: 'Could not load approved cities. Check your connection and retry.',
        );
      });
    }
  }

  Map<String, dynamic>? _findCityByLabel(
    List<Map<String, dynamic>> cities,
    String arabic,
    String english,
  ) {
    for (final city in cities) {
      if (city['name_ar'] == arabic || city['name_en'] == english) return city;
    }
    return null;
  }

  String _cityLabel(Map<String, dynamic>? city, BuildContext context) {
    if (city == null) return '';
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return (isArabic
            ? city['name_ar'] ?? city['name_en']
            : city['name_en'] ?? city['name_ar'])
        .toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppStrings.findRide(context)),
        actions: const [
          Padding(
            padding: EdgeInsetsDirectional.only(end: 16),
            child: LanguageThemeActions(showThemeToggle: false),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.findRideSub(context),
                style: theme.textTheme.bodyMedium,
              ),

              const SizedBox(height: 24),

              // بطاقة البحث الرئيسية المصممة حسب Figma
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // محطة الانطلاق (من)
                    InkWell(
                      onTap: () {
                        _showCityPicker(
                          title: AppStrings.fromCity(context),
                          onSelected: (city) =>
                              setState(() => _fromCity = city),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.trip_origin_rounded,
                              color: Color(0xFF10B981),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppStrings.fromCity(context),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _cityLabel(_fromCity, context),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: theme.hintColor,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // محطة الوصول (إلى)
                    InkWell(
                      onTap: () {
                        _showCityPicker(
                          title: AppStrings.toCity(context),
                          onSelected: (city) => setState(() => _toCity = city),
                        );
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.15),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFFEF4444),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppStrings.toCity(context),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _cityLabel(_toCity, context),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: theme.hintColor,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // التاريخ وعدد المقاعد جنباً إلى جنب
                    Row(
                      children: [
                        // التاريخ
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate,
                                firstDate: DateTime.now(),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 30),
                                ),
                              );
                              if (picked != null) {
                                setState(() => _selectedDate = picked);
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.dividerColor.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppStrings.date(context),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme.hintColor,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_selectedDate.day}/${_selectedDate.month}',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        // عدد المقاعد
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.dividerColor.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppStrings.seatsCount(context),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.hintColor,
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(
                                        Icons.remove_circle_outline_rounded,
                                        size: 22,
                                      ),
                                      onPressed: _seatsCount > 1
                                          ? () => setState(() => _seatsCount--)
                                          : null,
                                    ),
                                    Text(
                                      '$_seatsCount',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                        size: 22,
                                      ),
                                      onPressed: _seatsCount < 4
                                          ? () => setState(() => _seatsCount++)
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // زر البحث
                    ElevatedButton.icon(
                      onPressed:
                          _loadingCities ||
                              _fromCity == null ||
                              _toCity == null ||
                              _fromCity!['id'] == _toCity!['id']
                          ? null
                          : () {
                              context.push(
                                '/passenger/results',
                                extra: {
                                  'from': _cityLabel(_fromCity, context),
                                  'to': _cityLabel(_toCity, context),
                                  'fromCityId': _fromCity!['id'],
                                  'toCityId': _toCity!['id'],
                                  'date': _selectedDate,
                                  'seats': _seatsCount,
                                },
                              );
                            },
                      icon: const Icon(Icons.search_rounded),
                      label: Text(AppStrings.searchRidesBtn(context)),
                    ),
                  ],
                ),
              ),
              if (_loadingCities)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_cityLoadError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_cityLoadError!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCityPicker({
    required String title,
    required ValueChanged<Map<String, dynamic>> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _cities.length,
                  itemBuilder: (context, index) {
                    final city = _cities[index];
                    return ListTile(
                      title: Text(_cityLabel(city, context)),
                      onTap: () {
                        onSelected(city);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
