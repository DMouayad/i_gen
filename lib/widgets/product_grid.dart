import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:i_gen/controllers/cart_controller.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/size_picker.dart';

class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.products,
    required this.cart,
    this.priceOf,
    this.priceListenable,
  });

  final List<Product> products;
  final CartController cart;

  /// Null → order mode: no prices anywhere.
  final num? Function(Product)? priceOf;

  /// Notifier that fires when [priceOf] results change (price-list switch).
  /// Merged with [cart] so tiles re-resolve prices without a grid remount
  /// (scroll position survives the switch).
  final Listenable? priceListenable;

  @override
  Widget build(BuildContext context) {
    final extra = priceListenable;
    // ~30 tiles rebuilt per cart change: fine at this scale, no per-tile
    // listeners needed.
    return ListenableBuilder(
      listenable: extra == null ? cart : Listenable.merge([cart, extra]),
      builder: (context, _) => GridView.builder(
        padding: const EdgeInsets.all(AppGaps.sm),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: AppGaps.sm,
          crossAxisSpacing: AppGaps.sm,
          childAspectRatio: 0.9,
        ),
        itemCount: products.length,
        itemBuilder: (context, i) {
          final p = products[i];
          return _ProductTile(
            product: p,
            price: priceOf?.call(p),
            qty: cart.qtyOf(p),
            onTap: () => _onTap(context, p),
          );
        },
      ),
    );
  }

  void _onTap(BuildContext context, Product p) {
    if (p.hasSizes) {
      showSizePicker(context, product: p, cart: cart, priceOf: priceOf);
    } else {
      cart.add(p, size: p.singleSize, price: priceOf?.call(p));
    }
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.qty,
    this.price,
    required this.onTap,
  });

  final Product product;
  final int qty;
  final num? price;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final inCart = qty > 0;
    // In-cart text goes onPrimary per design (eyeball the contrast on
    // primaryContainer and say the word if it needs softening).
    final textColor = inCart ? colors.onPrimary : null;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.card),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: inCart
              ? colors.primaryContainer
              : colors.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(
            color: inCart ? colors.primary : colors.outlineVariant,
          ),
        ),
        padding: const EdgeInsets.all(AppGaps.sm),
        child: Stack(
          alignment: .center,
          children: [
            Align(
              alignment: AlignmentDirectional.topStart,
              child: Badge(
                isLabelVisible: inCart,
                label: Text('$qty', style: const TextStyle(fontSize: 12)),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: .center,
              children: [
                Text(
                  product.model,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                Text(
                  product.name,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                  ),
                  maxLines: 2,
                  textAlign: .center,
                  overflow: TextOverflow.ellipsis,
                ),
                if (price != null)
                  Text(
                    NumberFormat.decimalPattern().format(price),
                    style: context.textTheme.labelMedium?.copyWith(
                      color: textColor ?? colors.onSurfaceVariant,
                    ),
                  ),
                // Never show the size range: sizes are picked, not displayed.
              ],
            ),
          ],
        ),
      ),
    );
  }
}
