import 'package:flutter/material.dart';

import 'package:i_gen/controllers/cart_controller.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/utils/context_extensions.dart';

/// Size picker sheet: tap a size = +1, the sheet stays open so several
/// sizes can be filled in one go. Chip labels show the running quantity.
Future<void> showSizePicker(
  BuildContext context, {
  required Product product,
  required CartController cart,
  required num? Function(Product)? priceOf,
}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(AppGaps.md, 0, AppGaps.md, AppGaps.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${product.model} · ${product.name}',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppGaps.md),
          ListenableBuilder(
            listenable: cart,
            builder: (context, _) => Wrap(
              spacing: AppGaps.sm,
              runSpacing: AppGaps.sm,
              children: [
                for (final size in product.sizes)
                  ActionChip(
                    label: Text(
                      cart.qtyOfSize(product, size) > 0
                          ? '$size · ${cart.qtyOfSize(product, size)}'
                          : size,
                    ),
                    onPressed: () => cart.add(
                      product,
                      size: size,
                      price: priceOf?.call(product),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
