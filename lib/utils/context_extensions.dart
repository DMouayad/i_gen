import 'package:flutter/material.dart';
import 'package:i_gen/l10n/app_localizations.dart';

abstract final class AppGaps {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppRadii {
  static const double control = 8;
  static const double card = 16;
  static const double dialog = 12;
}

abstract final class AppColors {
  /// Edited-but-unsaved grid cells, shared by every trina grid.
  static const Color dirtyCell = Color(0xFFFFF3C4);
}

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
    color: colorScheme.onSurface,
  );
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => TextTheme.of(this);
}

extension LocalizationExtensions on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
