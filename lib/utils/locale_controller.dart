import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the app language (ar/en) and exposes it as a ValueNotifier
/// so MaterialApp.locale can rebuild live. Null means "follow system".
class LocaleController extends ValueNotifier<Locale?> {
  LocaleController._(super.value);

  static final LocaleController instance = LocaleController._(null);
  static const _kKey = 'app_locale';

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kKey);
    if (code != null && (code == 'ar' || code == 'en')) {
      instance.value = Locale(code);
    }
  }

  Future<void> setLocale(Locale? locale) async {
    value = locale;
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_kKey);
    } else {
      await prefs.setString(_kKey, locale.languageCode);
    }
  }

  Future<void> toggle() async {
    final current =
        value?.languageCode ??
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final next = current == 'ar' ? 'en' : 'ar';
    await setLocale(Locale(next));
  }

  String get currentCode =>
      value?.languageCode ??
      WidgetsBinding.instance.platformDispatcher.locale.languageCode;
}
