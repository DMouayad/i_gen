import 'package:flutter/material.dart';

import 'package:i_gen/controllers/cart_controller.dart';
import 'package:i_gen/models/cart_line.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/numbers.dart';
import 'package:i_gen/widgets/number_field.dart';

/// Cart sheet: one row per line plus an optional footer (invoice discount +
/// total; orders pass null). The row is the only stateful piece — it owns
/// the qty/price text controllers, scoped to the leaf instead of a
/// top-level list.
Future<void> showCartSheet(
  BuildContext context, {
  required CartController cart,
  required bool showPrices,
  String Function(num)? formatNumber,
  String? currency,

  /// Invoice discount + total; empty by default (orders pass nothing).
  Widget footer = const SizedBox.shrink(),
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => ListenableBuilder(
      listenable: cart,
      builder: (context, _) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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

  void _bumpQty(int delta) {
    final next = ((parseCanonicalInt(_qty.text) ?? 0) + delta).clamp(0, 999999);
    _qty.text = next == 0 ? '' : '$next';
    widget.cart.setQty(widget.line, next); // 0 removes the line
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
              if (line.product.hasSizes) _buildSizeMenu(context),
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
                onChanged: (raw) {
                  final qty = parseCanonicalInt(raw);
                  // The field never deletes: only steppers/X remove lines.
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
                    onChanged: (raw) {
                      final price = parseCanonicalDecimal(raw);
                      if (price == null || price < 0) return;
                      widget.cart.setPrice(line, price);
                    },
                  ),
                ),
                const SizedBox(width: AppGaps.sm),
                Text(
                  widget.formatNumber?.call(line.total) ?? '${line.total}',
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSizeMenu(BuildContext context) {
    return PopupMenuButton<String?>(
      initialValue: widget.line.size,
      onSelected: (s) => widget.cart.setSize(widget.line, s),
      itemBuilder: (_) => [
        for (final s in widget.line.product.sizes)
          PopupMenuItem(value: s, child: Text(s)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppGaps.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.line.size ?? ''),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
