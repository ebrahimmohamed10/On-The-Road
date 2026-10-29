import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/locale_provider.dart';
import '../../core/theme/theme_provider.dart';

class LanguageThemeActions extends ConsumerWidget {
  final bool showThemeToggle;
  const LanguageThemeActions({super.key, this.showThemeToggle = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArabic = ref.watch(localeProvider).languageCode == 'ar';
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // زر تبديل اللغة (عربي / English)
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: () {
            ref.read(localeProvider.notifier).toggleLocale();
          },
          icon: const Icon(Icons.language_rounded, size: 18),
          label: Text(
            isArabic ? 'English' : 'عربي',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        if (showThemeToggle) ...[
          const SizedBox(width: 8),
          IconButton.filledTonal(
            visualDensity: VisualDensity.compact,
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggleTheme();
            },
            icon: Icon(
              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 18,
            ),
            tooltip: isDark ? 'Light Mode' : 'Dark Mode',
          ),
        ],
      ],
    );
  }
}
