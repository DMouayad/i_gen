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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: context.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppGaps.md,
          vertical: AppGaps.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, size: 18),
            const SizedBox(width: AppGaps.sm),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
