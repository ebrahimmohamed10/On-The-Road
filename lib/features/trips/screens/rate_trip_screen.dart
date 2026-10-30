import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_strings.dart';

class RateTripScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? tripData;

  const RateTripScreen({super.key, this.tripData});

  @override
  ConsumerState<RateTripScreen> createState() => _RateTripScreenState();
}

class _RateTripScreenState extends ConsumerState<RateTripScreen> {
  int _selectedStars = 4;
  final Set<String> _selectedTags = {'safeDriver', 'onTime'};
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  /// All available rating tags — key matches AppStrings, kept in a fixed order
  static const _allTags = [
    'safeDriver',
    'onTime',
    'cleanCar',
    'friendly',
    'comfortableRoute',
    'polite',
    'funTrip',
  ];

  String _labelForTag(BuildContext context, String key) {
    return switch (key) {
      'safeDriver'       => AppStrings.tagSafeDriver(context),
      'onTime'           => AppStrings.tagOnTime(context),
      'cleanCar'         => AppStrings.tagCleanCar(context),
      'friendly'         => AppStrings.tagFriendly(context),
      'comfortableRoute' => AppStrings.tagComfortableRoute(context),
      'polite'           => AppStrings.tagPolite(context),
      'funTrip'          => AppStrings.tagFunTrip(context),
      _                  => key,
    };
  }

  String _ratingLabel(BuildContext context, int stars) {
    return switch (stars) {
      1 => AppStrings.ratingPoor(context),
      2 => AppStrings.ratingFair(context),
      3 => AppStrings.ratingGood(context),
      4 => AppStrings.ratingExcellent(context),
      5 => AppStrings.ratingPerfect(context),
      _ => '',
    };
  }

  Future<void> _submit() async {
    setState(() => _isSubmitting = true);
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    context.go('/passenger/bookings');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.ratingSubmitted(context)),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final driverName  = widget.tripData?['driverName']  ?? (AppStrings.isArabic(context) ? 'أحمد حسن' : 'Ahmed Hassan');
    final initials    = widget.tripData?['initials']    ?? (AppStrings.isArabic(context) ? 'أح' : 'AH');
    final route       = widget.tripData?['route']       ?? (AppStrings.isArabic(context) ? 'القاهرة ← الإسكندرية' : 'Cairo → Alexandria');
    final dateLabel   = widget.tripData?['dateLabel']   ?? (AppStrings.isArabic(context) ? '٢٨ أكتوبر' : '28 Oct');

    return Scaffold(
      backgroundColor: isDark ? theme.scaffoldBackgroundColor : const Color(0xFFF8F9FB),
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header bar ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.dividerColor.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ),
                  ),
                  Text(
                    AppStrings.rateYourTrip(context),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // ─── Scrollable body ─────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // ── Driver Card ──────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: const Color(0xFFEEF2FF),
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: Color(0xFF4F46E5),
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            driverName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$route · $dateLabel',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Star Rating ──────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (i) {
                        final starNum = i + 1;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedStars = starNum),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.star_rounded,
                              size: 40,
                              color: starNum <= _selectedStars
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 8),

                    // Rating label
                    Text(
                      _ratingLabel(context, _selectedStars),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── "What went well?" section ────────────────
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        AppStrings.whatWentWell(context),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _allTags.map((tag) {
                          final selected = _selectedTags.contains(tag);
                          return GestureDetector(
                            onTap: () => setState(() {
                              if (selected) {
                                _selectedTags.remove(tag);
                              } else {
                                _selectedTags.add(tag);
                              }
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFF59E0B)
                                    : theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(50),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFFF59E0B)
                                      : theme.dividerColor.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                _labelForTag(context, tag),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : const Color(0xFF374151)),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── Comment field ────────────────────────────
                    TextField(
                      controller: _commentController,
                      maxLines: 4,
                      minLines: 3,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: AppStrings.writeCommentHint(context),
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: theme.hintColor,
                        ),
                        filled: true,
                        fillColor: theme.colorScheme.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: theme.dividerColor.withValues(alpha: 0.2),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: theme.dividerColor.withValues(alpha: 0.2),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFFF59E0B),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ─── Bottom action area ───────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                children: [
                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F172A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text(
                              AppStrings.submitRating(context),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Skip link
                  GestureDetector(
                    onTap: () => context.go('/passenger/bookings'),
                    child: Text(
                      AppStrings.skipRating(context),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
