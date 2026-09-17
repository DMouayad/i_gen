import 'package:flutter/material.dart';

import 'package:i_gen/controllers/cart_controller.dart';
import 'package:i_gen/utils/context_extensions.dart';

/// Bottom bar for the cart flow: live item count on the left, view-cart,
/// preview, and save actions on the right. The invoice total lives in the
/// AppBar; this bar stays count-only.
class CartBar extends StatelessWidget {
  const CartBar({
    super.key,
    required this.cart,
    required this.onOpenCart,
    required this.onPreview,
    required this.onSave,
  });

  final CartController cart;
  final VoidCallback onOpenCart;
  final VoidCallback onPreview;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: context.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: context.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          children: [
            ListenableBuilder(
              listenable: cart,
              builder: (context, _) => Badge(
                isLabelVisible: !cart.isEmpty,
                label: Text('${cart.itemCount}'),
                child: IconButton(
                  onPressed: cart.isEmpty ? null : onOpenCart,
                  icon: const Icon(Icons.shopping_cart_outlined),
                  tooltip: context.l10n.itemsCount(cart.itemCount),
                ),
              ),
            ),
            const Spacer(),
            TextButton.icon(
              label: Text(context.l10n.previewButton),
              icon: const Icon(Icons.preview_outlined),
              onPressed: onPreview,
            ),
            const SizedBox(width: AppGaps.md),
            FilledButton.icon(
              onPressed: onSave,
              icon: const Icon(Icons.check, size: 18),
              label: Text(context.l10n.saveButton),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
