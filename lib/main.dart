import 'dart:io';

import 'package:flutter/material.dart';
import 'package:i_gen/di.dart';
import 'package:i_gen/l10n/app_localizations.dart';
import 'package:i_gen/screens/home_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  if (Platform.isWindows || Platform.isLinux) {
    // Initialize FFI
    sqfliteFfiInit();
  }
  databaseFactory = databaseFactoryFfi;

  // register deps
  await injectDependencies();

  runApp(const MainApp());
}

final isDesktop = Platform.isWindows || Platform.isLinux;

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
          seedColor: Colors.lightBlue,
        ),
        textTheme: Typography.material2021().black.apply(
          fontFamily: 'Noto Naskh Arabic',
        ),
      ),
      home: Home(),
    );
  }
}
