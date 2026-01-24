import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:i_gen/utils/context_extensions.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final ValueChanged<String> onChanged;
  final String? initialValue;

  const CustomTextField({
    super.key,
    required this.label,
    required this.onChanged,
    this.controller,
    this.initialValue,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(width: 1, color: context.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(width: 2, color: context.colorScheme.primary),
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
      onChanged: onChanged,
    );
  }
}
