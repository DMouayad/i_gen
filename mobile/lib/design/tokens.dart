import 'package:flutter/material.dart';

/// Dart mirror of `design/design-tokens.json` (repo root).
///
/// That file is the single source of truth — change it first, then mirror
/// the values here. Never invent palette values inline in widgets; extend
/// this file (and the JSON) instead.
abstract final class BrandColors {
  static const Color primary = Color(0xFF1F497D);
  static const Color primaryDeep = Color(0xFF142E4F);
  static const Color brandLight = Color(0xFFE9EEF5);

  static const Color surface0 = Color(0xFFFFFFFF);
  static const Color surface1 = Color(0xFFFBFAF8);
  static const Color surface2 = Color(0xFFF5EFE7);
  static const Color surface3 = Color(0xFFEDF1F7);

  static const Color textPrimary = Color(0xFF0A1F24);

  /// Slate gray: holds AA contrast on the ivory surfaces.
  static const Color textMuted = Color(0xFF64748B);

  static const Color border = Color(0xFFE2DDD2);

  static const Color beige = Color(0xFFE8DFCF);
  static const Color beigeHighlight = Color(0xFFF5EEE4);
  static const Color beigeShadow = Color(0xFFBFAE99);
}

/// Font families bundled in `assets/` (see `pubspec.yaml`).
abstract final class BrandFonts {
  static const String sans = 'Readex Pro';
  static const String arabic = 'Noto Naskh Arabic';

  /// Arabic fallback for every text style: Readex covers Latin + some
  /// Arabic, Plex carries the Arabic headings/body.
  static const List<String> sansFallback = [sans];
}
