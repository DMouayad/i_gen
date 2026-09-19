import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/design/tokens.dart';
import 'package:i_gen/di.dart';
import 'package:i_gen/l10n/app_localizations.dart';
import 'package:i_gen/screens/home_screen.dart';
import 'package:i_gen/screens/invite_accept_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/locale_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
final _appLinks = AppLinks();

/// Routes tapped WhatsApp invite links (Android intent) to the accept
/// screen. Only our callback scheme is honored; everything else is ignored.
/// Failures here must never break startup.
Future<void> _watchInviteLinks() async {
  try {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) _openInviteLink(initial);
  } catch (e) {
    debugPrint('InviteLinks: initial link failed: $e');
  }
  _appLinks.uriLinkStream.listen(
    _openInviteLink,
    onError: (Object e) {
      debugPrint('InviteLinks: stream failed: $e');
    },
  );
}

void _openInviteLink(Uri uri) {
  if (uri.scheme != 'io.invogen.app') return;
  _navigatorKey.currentState?.push(
    MaterialPageRoute(builder: (_) => InviteAcceptScreen(link: uri.toString())),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    // Initialize FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Auth first: restores the persisted session (offline-safe, never throws).
  // The app remains fully usable when signed out or unconfigured.
  await AuthService.initialize();
  await LocaleController.initialize();

  // register deps
  await injectDependencies();

  runApp(const MainApp());
  unawaited(_watchInviteLinks());
}

final isDesktop = Platform.isWindows || Platform.isLinux;

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          seedColor: BrandColors.primary,
        ).copyWith(
          // Seed math drifts toward gray-green; pin the surfaces to the token
          // ivory so both apps share the same background language.
          surface: BrandColors.surface1,
        );
    return ValueListenableBuilder<Locale?>(
      valueListenable: LocaleController.instance,
      builder: (context, locale, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          title: 'I-Gen',
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.0)),
              child: child!,
            );
          },
          theme: ThemeData.light().copyWith(
            visualDensity: VisualDensity.adaptivePlatformDensity,
            colorScheme: scheme,
            scaffoldBackgroundColor: scheme.surface,
            textTheme: Typography.material2021().black.apply(
              fontFamily: BrandFonts.sans,
              fontFamilyFallback: BrandFonts.sansFallback,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            dialogTheme: DialogThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.dialog),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            ),
            bottomNavigationBarTheme: BottomNavigationBarThemeData(
              backgroundColor: scheme.surfaceContainer,
              selectedItemColor: scheme.primary,
              unselectedItemColor: scheme.onSurfaceVariant,
              type: BottomNavigationBarType.fixed,
            ),
            navigationRailTheme: NavigationRailThemeData(
              backgroundColor: scheme.surface,
              selectedIconTheme: IconThemeData(color: scheme.onSurface),
              unselectedIconTheme: IconThemeData(
                color: scheme.onSurfaceVariant,
              ),
              selectedLabelTextStyle: TextStyle(color: scheme.primary),
              unselectedLabelTextStyle: TextStyle(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          home: const Home(),
        );
      },
    );
  }
}
