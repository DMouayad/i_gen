import 'package:flutter/material.dart';
import 'package:i_gen/utils/context_extensions.dart';

/// Shared read-only notice for catalog screens (products, pricing).
/// Shown when the signed-in role may view but not edit the catalog.
class ReadOnlyBanner extends StatelessWidget {
  const ReadOnlyBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
