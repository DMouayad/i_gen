import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/di.dart';
import 'package:i_gen/l10n/app_localizations.dart';
import 'package:i_gen/screens/home_screen.dart';
import 'package:i_gen/screens/invite_accept_screen.dart';
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
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
        scaffoldBackgroundColor: Color(0xFFF8F8F8),
        colorScheme: ColorScheme.fromSeed(
          dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
          seedColor: const Color.fromARGB(255, 16, 94, 197),
        ),
        textTheme: Typography.material2021().black.apply(
          fontFamily: 'Noto Naskh Arabic',
        ),
      ),
      home: const Home(),
    );
  }
}
