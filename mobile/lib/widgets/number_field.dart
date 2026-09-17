import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:i_gen/utils/context_extensions.dart';

/// Numeric text field with tabular figures and an optional suffix.
/// Parsing is the caller's job ([parseCanonicalInt]/[parseCanonicalDecimal]
/// in `utils/numbers.dart`); this widget only owns the look and keyboard.
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    this.onChanged,
    this.allowDecimal = false,
    this.suffix,
    this.width,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final bool allowDecimal;
  final String? suffix;
  final double? width;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      keyboardType: allowDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: allowDecimal
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,٫٠-٩۰-۹]'))]
          : [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.end,
      style: context.textTheme.bodyMedium?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        suffixText: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      onChanged: onChanged,
    );
    if (width == null) return field;
    return SizedBox(width: width, child: field);
  }
}
