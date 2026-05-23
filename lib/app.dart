import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'screens/about_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/page_editor_screen.dart';
import 'screens/pdf_import_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/settings_screen.dart';
import 'services/prefs_service.dart';
import 'state/locale_notifier.dart';
import 'state/settings_notifier.dart';

class PictureBookApp extends StatelessWidget {
  const PictureBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>();
    final localeNotifier = context.watch<LocaleNotifier>();
    // Lock to landscape on tablets (shortest side >= 600).
    final mq = MediaQueryData.fromView(View.of(context));
    final tablet = mq.size.shortestSide >= 600;
    if (tablet) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }

    final lightScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF4F6DDE));
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F6DDE),
      brightness: Brightness.dark,
    );

    final fontFamily = settings.dyslexiaFont ? 'OpenDyslexic' : null;

    return MaterialApp(
      title: 'Picture Book',
      themeMode: settings.themeMode,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        fontFamily: fontFamily,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontSize: 24),
          headlineMedium: TextStyle(fontSize: 28),
          bodyLarge: TextStyle(fontSize: 18),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: lightScheme.primary,
          foregroundColor: lightScheme.onPrimary,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        fontFamily: fontFamily,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      locale: localeNotifier.locale,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppStrings.supportedLocales,
      builder: (context, child) {
        // Cap text scaling to 2.0 so layouts don't blow up.
        final mediaQuery = MediaQuery.of(context);
        final scaled = mediaQuery.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 2.0,
        );
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: scaled),
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute:
          context.read<PrefsService>().onboardingDone ? '/' : '/onboarding',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const ReaderScreen());
          case '/onboarding':
            return MaterialPageRoute(builder: (_) => const OnboardingScreen());
          case '/admin':
            return MaterialPageRoute(builder: (_) => const AdminScreen());
          case '/admin/page-editor':
            final args = settings.arguments;
            if (args is Map<String, Object?>) {
              return MaterialPageRoute(
                builder: (_) => PageEditorScreen(
                  args: PageEditorArgs.fromMap(args),
                ),
              );
            }
            return null;
          case '/settings':
            return MaterialPageRoute(builder: (_) => const SettingsScreen());
          case '/admin/pdf-import':
            return MaterialPageRoute(builder: (_) => const PdfImportScreen());
          case '/about':
            return MaterialPageRoute(builder: (_) => const AboutScreen());
        }
        return null;
      },
    );
  }
}
