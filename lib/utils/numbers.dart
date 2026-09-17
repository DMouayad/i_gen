/// Canonical number parsing shared by every numeric field.
///
/// Digits arrive in three scripts (ASCII, Arabic-Indic ٠-٩, Extended
/// Arabic-Indic ۰-۹) and decimals with `.` or `٫`; both are folded to
/// canonical ASCII before parsing. Extracted from the old mobile line
/// editor so the cart sheet and any future field share one behavior.
String canonicalNumber(String raw) {
  final trimmed = raw.trim();
  final isNegative = trimmed.startsWith('-');
  final sb = StringBuffer();
  for (final rune in raw.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      sb.writeCharCode(rune);
    } else if (rune >= 0x660 && rune <= 0x669) {
      sb.writeCharCode(rune - 0x660 + 0x30);
    } else if (rune >= 0x6F0 && rune <= 0x6F9) {
      sb.writeCharCode(rune - 0x6F0 + 0x30);
    } else if (rune == 0x66B || rune == 0x2E) {
      sb.write('.');
    }
  }
  final canonical = sb.toString();
  return isNegative && canonical.isNotEmpty ? '-$canonical' : canonical;
}

/// Parses a quantity field: empty → 0, non-numeric → null.
int? parseCanonicalInt(String raw) {
  final canonical = canonicalNumber(raw);
  if (canonical.isEmpty) return 0;
  return int.tryParse(canonical);
}

/// Parses a decimal field: empty → 0, malformed → null.
num? parseCanonicalDecimal(String raw) {
  final canonical = canonicalNumber(raw);
  if (canonical.isEmpty) return 0;
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(canonical)) return null;
  return num.tryParse(canonical);
}
