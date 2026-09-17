import 'package:flutter/material.dart';

import 'package:i_gen/controllers/cart_controller.dart';
import 'package:i_gen/models/cart_line.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/numbers.dart';
import 'package:i_gen/widgets/number_field.dart';

Future<void> showCartSheet(
  BuildContext context, {
  required CartController cart,
  required bool showPrices,
  String Function(num)? formatNumber,
  String? currency,
  Widget footer = const SizedBox.shrink(),
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true, // tall carts stay below the status bar
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Padding(
        // Keyboard avoidance. viewInsetsOf (not MediaQuery.of) so the sheet
        // rebuilds only when the keyboard moves, not on any resize.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The scrim hides the AppBar, so the sheet states its own count.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                context.l10n.itemsCount(cart.itemCount),
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (cart.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 32,
                ),
                child: Text(
                  'cartEmpty',
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: AppGaps.sm),
                  children: [
                    for (final line in cart.lines)
                      _CartRow(
                        key: ObjectKey(line),
                        line: line,
                        cart: cart,
                        showPrices: showPrices,
                        formatNumber: formatNumber,
                        currency: currency,
                      ),
                  ],
                ),
              ),
            footer,
          ],
        ),
      ),
    ),
  );
}

class _CartRow extends StatefulWidget {
  const _CartRow({
    super.key,
    required this.line,
    required this.cart,
    required this.showPrices,
    this.formatNumber,
    this.currency,
  });

  final CartLine line;
  final CartController cart;
  final bool showPrices;
  final String Function(num)? formatNumber;
  final String? currency;

  @override
  State<_CartRow> createState() => _CartRowState();
}

class _CartRowState extends State<_CartRow> {
  late final _qty = TextEditingController(
    text: widget.line.qty == 0 ? '' : '${widget.line.qty}',
  );
  late final _price = TextEditingController(
    text: widget.line.unitPrice == 0
        ? ''
        : widget.formatNumber?.call(widget.line.unitPrice) ??
              '${widget.line.unitPrice}',
  );

  @override
  void dispose() {
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  // Steppers and the price-list switch change the line from outside.
  // Qty: the stepper writes the field itself, so no sync needed. Price:
  // only non-overridden lines get repriced, and the user's first keystroke
  // flips priceOverridden — so syncing unoverridden lines never fights
  // an in-progress edit.
  @override
  void didUpdateWidget(covariant _CartRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showPrices && !widget.line.priceOverridden) {
      final shown = parseCanonicalDecimal(_price.text);
      if (shown != widget.line.unitPrice) {
        _price.text = widget.line.unitPrice == 0
            ? ''
            : widget.formatNumber?.call(widget.line.unitPrice) ??
                  '${widget.line.unitPrice}';
      }
    }
  }

  void _unfocus() => FocusScope.of(context).unfocus();

  // Steppers never delete: minus stops at 1. X is the only remover, so a
  // clumsy tap can't destroy a line's size + hand-typed price.
  void _bumpQty(int delta) {
    final current = parseCanonicalInt(_qty.text) ?? 0;
    if (delta < 0 && current <= 1) return;
    final next = (current + delta).clamp(1, 999999);
    _qty.text = '$next';
    widget.cart.setQty(widget.line, next);
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppGaps.md,
        vertical: AppGaps.sm,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${line.product.model} · ${line.product.name}',
                  style: context.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => widget.cart.remove(line),
                tooltip: context.l10n.removeButton,
              ),
            ],
          ),
          const SizedBox(height: AppGaps.xs),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () => _bumpQty(-1),
              ),
              NumberField(
                controller: _qty,
                width: 64,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _unfocus(),
                onChanged: (raw) {
                  final qty = parseCanonicalInt(raw);
                  // The field never deletes: only X removes lines.
                  if (qty == null || qty <= 0) return;
                  widget.cart.setQty(line, qty);
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _bumpQty(1),
              ),
              if (widget.showPrices) ...[
                const SizedBox(width: AppGaps.sm),
                Expanded(
                  child: NumberField(
                    controller: _price,
                    allowDecimal: true,
                    suffix: widget.currency,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _unfocus(),
                    onChanged: (raw) {
                      final price = parseCanonicalDecimal(raw);
                      if (price == null || price < 0) return;
                      widget.cart.setPrice(line, price);
                    },
                  ),
                ),
                const SizedBox(width: AppGaps.sm),
                // Money never ellipsizes — scale down instead.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      widget.formatNumber?.call(line.total) ?? '${line.total}',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
