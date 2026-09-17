import 'package:flutter/material.dart';

import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/numbers.dart';
import 'package:i_gen/widgets/number_field.dart';

/// Discount row for the cart sheet footer (mobile and desktop share it).
/// Writes straight into the controller; the invoice total is lines-only,
/// so no total refresh is needed — only the unsaved flag.
class InvoiceDiscountFooter extends StatefulWidget {
  const InvoiceDiscountFooter({super.key, required this.controller});

  final InvoiceDetailsController controller;

  @override
  State<InvoiceDiscountFooter> createState() => _InvoiceDiscountFooterState();
}

class _InvoiceDiscountFooterState extends State<InvoiceDiscountFooter> {
  late final TextEditingController _discount = TextEditingController(
    text: widget.controller.discount == 0
        ? ''
        : '${widget.controller.discount}',
  );

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Row(
        children: [
          Text(
            context.l10n.discount,
            style: context.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          ValueListenableBuilder(
            valueListenable: widget.controller.priceCategoryNotifier,
            builder: (context, category, _) => NumberField(
              controller: _discount,
              width: 120,
              allowDecimal: true,
              suffix: category.currency,
              onChanged: (raw) {
                final parsed = parseCanonicalDecimal(raw);
                if (parsed == null) return;
                widget.controller.discount = parsed.toDouble();
                widget.controller.hasUnsavedChanges = true;
              },
            ),
          ),
        ],
      ),
    );
  }
}
