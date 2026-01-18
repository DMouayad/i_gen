import 'package:flutter/material.dart';
import 'package:i_gen/l10n/app_localizations.dart';

extension ScreenExtensions on BuildContext {
  double get width => MediaQuery.of(this).size.width;
  double get height => MediaQuery.of(this).size.height;
  bool get showNavigationRail => width > 600 && height > 600;
  bool get isMobile => width < 600;
}

extension ThemeExtensions on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
}

extension TextStylesExtensions on BuildContext {
  TextStyle get errorTextStyle => TextStyle(color: colorScheme.error);
  TextStyle get defaultTextStyle => textTheme.bodyLarge!.copyWith(
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => TextTheme.of(this);
}

extension LocalizationExtensions on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
