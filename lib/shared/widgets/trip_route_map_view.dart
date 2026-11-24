import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_strings.dart';

class TripRouteMapView extends StatelessWidget {
  final String originCity;
  final String destinationCity;
  final String? originStation;
  final String? destinationStation;
  final List<String>? waypoints;
  final double height;
  final bool showOpenInGoogleMaps;

  const TripRouteMapView({
    super.key,
    required this.originCity,
    required this.destinationCity,
    this.originStation,
    this.destinationStation,
    this.waypoints,
    this.height = 220,
    this.showOpenInGoogleMaps = true,
  });

  static const Map<String, LatLng> _knownCoordinates = {
    'cairo': LatLng(30.0444, 31.2357),
    'القاهرة': LatLng(30.0444, 31.2357),
    'alexandria': LatLng(31.2001, 29.9187),
    'الإسكندرية': LatLng(31.2001, 29.9187),
    'giza': LatLng(30.0131, 31.2089),
    'الجيزة': LatLng(30.0131, 31.2089),
    'tanta': LatLng(30.7865, 31.0004),
    'طنطا': LatLng(30.7865, 31.0004),
    'mansoura': LatLng(31.0409, 31.3785),
    'المنصورة': LatLng(31.0409, 31.3785),
    'ismailia': LatLng(30.5965, 32.2715),
    'الإسماعيلية': LatLng(30.5965, 32.2715),
    'suez': LatLng(29.9668, 32.5498),
    'السويس': LatLng(29.9668, 32.5498),
    'portsaid': LatLng(31.2653, 32.3019),
    'بورسعيد': LatLng(31.2653, 32.3019),
    'damanhour': LatLng(31.0379, 30.4725),
    'دمنهور': LatLng(31.0379, 30.4725),
    'banha': LatLng(30.4660, 31.1853),
    'بنها': LatLng(30.4660, 31.1853),
    'zagazig': LatLng(30.5877, 31.5020),
    'الزقازيق': LatLng(30.5877, 31.5020),
    'asyut': LatLng(27.1783, 31.1859),
    'أسيوط': LatLng(27.1783, 31.1859),
    'sohag': LatLng(26.5569, 31.6948),
    'سوهاج': LatLng(26.5569, 31.6948),
    'qena': LatLng(26.1551, 32.7160),
    'قنا': LatLng(26.1551, 32.7160),
    'luxor': LatLng(25.6872, 32.6396),
    'الأقصر': LatLng(25.6872, 32.6396),
    'aswan': LatLng(24.0889, 32.8998),
    'أسوان': LatLng(24.0889, 32.8998),
    'hurghada': LatLng(27.2579, 33.8116),
    'الغردقة': LatLng(27.2579, 33.8116),
    'sharm': LatLng(27.9158, 34.3299),
    'شرم الشيخ': LatLng(27.9158, 34.3299),
  };

  LatLng _coordFor(String name, [LatLng fallback = const LatLng(30.0444, 31.2357)]) {
    final clean = name.trim().toLowerCase();
    for (final entry in _knownCoordinates.entries) {
      if (clean.contains(entry.key.toLowerCase()) || entry.key.toLowerCase().contains(clean)) {
        return entry.value;
      }
    }
    return fallback;
  }

  Future<void> _openGoogleMaps(BuildContext context) async {
    final originQuery = originStation?.isNotEmpty == true
        ? '$originStation, $originCity, Egypt'
        : '$originCity, Egypt';
    final destQuery = destinationStation?.isNotEmpty == true
        ? '$destinationStation, $destinationCity, Egypt'
        : '$destinationCity, Egypt';

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=${Uri.encodeComponent(originQuery)}&destination=${Uri.encodeComponent(destQuery)}&travelmode=driving',
    );

    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppStrings.tr(
                context,
                ar: 'تعذر فتح خرائط جوجل على الجهاز.',
                en: 'Could not open Google Maps on this device.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final originLatLng = _coordFor(originCity, const LatLng(30.0444, 31.2357));
    final destLatLng = _coordFor(destinationCity, const LatLng(31.2001, 29.9187));

    final routePoints = <LatLng>[originLatLng];
    if (waypoints != null) {
      for (final w in waypoints!) {
        routePoints.add(_coordFor(w));
      }
    }
    routePoints.add(destLatLng);

    final centerLat = (originLatLng.latitude + destLatLng.latitude) / 2;
    final centerLng = (originLatLng.longitude + destLatLng.longitude) / 2;
    final centerLatLng = LatLng(centerLat, centerLng);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: centerLatLng,
                    initialZoom: 6.8,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.ontheroad.app.on_the_road',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          strokeWidth: 4.0,
                          color: const Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: originLatLng,
                          width: 38,
                          height: 38,
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFF10B981),
                            size: 34,
                          ),
                        ),
                        Marker(
                          point: destLatLng,
                          width: 38,
                          height: 38,
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFFEF4444),
                            size: 34,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$originCity ➔ $destinationCity',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showOpenInGoogleMaps)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: theme.colorScheme.surface,
              child: Row(
                children: [
                  const Icon(
                    Icons.navigation_rounded,
                    color: Color(0xFFF59E0B),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.tr(
                        context,
                        ar: 'توجيه حي وملاحة خطوة بخطوة',
                        en: 'Live GPS navigation & directions',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.hintColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openGoogleMaps(context),
                    icon: const Icon(Icons.open_in_new_rounded, size: 14),
                    label: Text(
                      AppStrings.tr(
                        context,
                        ar: 'خرائط Google',
                        en: 'Google Maps',
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
