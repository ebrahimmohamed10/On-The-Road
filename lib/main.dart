import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/locale_provider.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // إعداد اتجاه الشاشة — عمودي فقط
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Supabase values are supplied using --dart-define at build/run time.
  // Do not build the normal app when initialization fails: providers and
  // services use Supabase.instance and would otherwise crash later.
  String? startupError;
  if (!AppConstants.isSupabaseConfigured) {
    startupError =
        'Supabase is not configured. Run the app with SUPABASE_URL and '
        'SUPABASE_ANON_KEY dart-defines.';
  } else if (!AppConstants.supabaseUrl.startsWith('https://')) {
    startupError = 'SUPABASE_URL must start with https://.';
  } else {
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        publishableKey: AppConstants.supabaseAnonKey,
      );
    } catch (error, stackTrace) {
      debugPrint('Supabase initialization error: $error');
      debugPrintStack(stackTrace: stackTrace);
      startupError = 'Supabase could not be initialized.\n\n$error';
    }
  }

  if (startupError case final message?) {
    runApp(SupabaseStartupErrorApp(message: message));
  } else {
    runApp(const ProviderScope(child: OnTheRoadApp()));
  }
}

class SupabaseStartupErrorApp extends StatelessWidget {
  const SupabaseStartupErrorApp({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(message, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}

class OnTheRoadApp extends ConsumerWidget {
  const OnTheRoadApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final currentLocale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,

      // إعداد الثيم الفاتح والداكن وزر التبديل
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,

      // لغة التطبيق الديناميكية (عربي / English)
      locale: currentLocale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // نظام التوجيه والتنقل
      routerConfig: router,
    );
  }
}
