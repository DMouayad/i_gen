import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_details_mobile.dart';

import 'custom_text_field.dart';

class InvoiceLineCard extends StatelessWidget {
  const InvoiceLineCard({
    super.key,
    required this.index,
    required this.lineData,
    required this.products,
    required this.currency,
    required this.formatNumber,
    required this.onRemove,
    required this.onProductSelected,
    required this.onAmountChanged,
    required this.onPriceChanged,
  });

  final int index;
  final InvoiceLineData lineData;
  final Map<String, Product> products;
  final String currency;
  final String Function(num) formatNumber;
  final VoidCallback onRemove;
  final ValueChanged<String> onProductSelected;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<String> onPriceChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final total = lineData.row.lineTotal;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                _LineNumber(index: index + 1),
                const SizedBox(width: 12),
                Expanded(child: _buildProductField()),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: colors.error),
                  onPressed: onRemove,
                  tooltip: 'Remove',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: CustomTextField(
                    label: 'Qty',
                    controller: lineData.amountController,
                    onChanged: onAmountChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: CustomTextField(
                    label: 'Price',
                    controller: lineData.priceController,
                    onChanged: onPriceChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _TotalBadge(
                    total: total,
                    currency: currency,
                    formatNumber: formatNumber,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductField() {
    return TypeAheadField<String>(
      controller: lineData.productController,
      builder: (context, controller, focusNode) => TextField(
        controller: controller,
        focusNode: focusNode,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          hintText: 'Search product...',
          prefixIcon: const Icon(Icons.inventory_2_outlined, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          isDense: true,
        ),
      ),
      onSelected: (value) {
        onProductSelected(value);
        lineData.productController.text = value;
      },
      itemBuilder: (context, name) {
        final product = products.values.firstWhere(
          (p) => p.name == name,
          orElse: () => Product(id: -1, model: '', name: name),
        );
        return ListTile(
          dense: true,
          title: Text(
            '${product.model}: $name',
            style: context.textTheme.bodyLarge,
          ),
        );
      },
      suggestionsCallback: (query) => products.values
          .where(
            (p) =>
                p.name.toLowerCase().contains(query.toLowerCase()) ||
                p.model.toLowerCase().contains(query.toLowerCase()),
          )
          .map((e) => e.name)
          .toList(),
      emptyBuilder: (_) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No products found'),
      ),
    );
  }
}

class _LineNumber extends StatelessWidget {
  const _LineNumber({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          '$index',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colors.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

class _TotalBadge extends StatelessWidget {
  const _TotalBadge({
    required this.total,
    required this.currency,
    required this.formatNumber,
  });
  final num total;
  final String currency;
  final String Function(num) formatNumber;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        formatNumber(total),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: colors.primary,
        ),
      ),
    );
  }
}
