import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier لإدارة لغة التطبيق الحالية (عربي / English)
class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('ar'); // العربية افتراضياً

  void toggleLocale() {
    state = state.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
  }

  void setLocale(String languageCode) {
    state = Locale(languageCode);
  }

  bool get isArabic => state.languageCode == 'ar';
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(() {
  return LocaleNotifier();
});

