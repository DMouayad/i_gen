import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:get_it/get_it.dart';

import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/utils/futuristic.dart';

class InvoiceLineData {
  final TextEditingController productController;
  final TextEditingController amountController;
  final TextEditingController priceController;
  InvoiceTableRow row;

  InvoiceLineData({required this.row})
    : productController = TextEditingController(text: row.product.name),
      amountController = TextEditingController(
        text: row.amount == 0 ? '' : row.amount.toString(),
      ),
      priceController = TextEditingController(
        text: row.unitPrice == 0 ? '' : row.unitPrice.toString(),
      );

  void dispose() {
    productController.dispose();
    amountController.dispose();
    priceController.dispose();
  }

  void updatePrice(num price, String Function(num) formatter) {
    priceController.text = price == 0 ? '' : formatter(price);
  }
}

class InvoiceLineInputMobile extends StatefulWidget {
  const InvoiceLineInputMobile({super.key, required this.controller});
  final InvoiceDetailsController controller;

  @override
  State<InvoiceLineInputMobile> createState() => _InvoiceLineInputMobileState();
}

class _InvoiceLineInputMobileState extends State<InvoiceLineInputMobile> {
  final List<InvoiceLineData> _lines = [];
  ProductsPricing? _productsPricing;
  ({String currency, String? name}) _priceCategory = (
    currency: 'USD',
    name: null,
  );

  Map<String, Product> get _products =>
      GetIt.I.get<ProductsController>().products;
  Timer? _debounce;
  @override
  void initState() {
    super.initState();
    _initializeLines();
    _fetchPricingData();
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _initializeLines() {
    final existingRows = widget.controller.invoiceLines;
    if (existingRows.isEmpty) {
      _lines.add(InvoiceLineData(row: _createEmptyRow()));
    } else {
      _lines.addAll(existingRows.map((row) => InvoiceLineData(row: row)));
    }
  }

  Future<void> _fetchPricingData() async {
    _productsPricing = await GetIt.I
        .get<ProductPricingRepo>()
        .getProductsPricing();
    if (widget.controller.invoice?.currency case String currency) {
      _priceCategory = (currency: currency, name: null);
    }
    if (mounted) setState(() {});
  }

  InvoiceTableRow _createEmptyRow() => InvoiceTableRow(
    unitPrice: 0,
    amount: 0,
    product: Product(id: -1, model: '', name: ''),
  );

  // ===== Line Operations =====

  void _addLine() {
    setState(() {
      _lines.add(InvoiceLineData(row: _createEmptyRow()));
      _markUnsaved();
    });
  }

  void _removeLine(int index) {
    if (index < 0 || index >= _lines.length) return;
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
      if (_lines.isEmpty) _addLine();
      _markUnsaved();
    });
  }

  void _updateProduct(int index, String productName) {
    final product = _products.values.firstWhere(
      (p) => p.name == productName,
      orElse: () => Product(id: -1, model: '', name: ''),
    );
    if (product.model.isEmpty) return;

    setState(() {
      final newPrice = _getProductPrice(product.model) ?? 0;
      _lines[index].row = _lines[index].row.copyWith(
        product: product,
        unitPrice: newPrice,
      );
      _lines[index].updatePrice(newPrice, _formatNumber);
      _markUnsaved();
    });
    _saveLines();
  }

  void _updateAmount(int index, String value) {
    final amount = int.tryParse(value) ?? 0;
    if (amount >= 0) {
      _lines[index].row = _lines[index].row.copyWith(amount: amount);
      _markUnsaved();
      setState(() {});
      _saveLines();
    }
  }

  void _updatePrice(int index, String value) {
    final price = num.tryParse(value.replaceAll(',', '')) ?? 0;
    if (price >= 0) {
      _lines[index].row = _lines[index].row.copyWith(unitPrice: price);
      _markUnsaved();
      setState(() {});
      _saveLines();
    }
  }

  void _updateDiscount(String discount) {
    widget.controller.discountNotifier.value =
        num.tryParse(discount)?.toDouble() ?? 0;
  }

  void _saveLines() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      // Sync controller values
      for (final line in _lines) {
        final amount = int.tryParse(line.amountController.text) ?? 0;
        final price =
            num.tryParse(line.priceController.text.replaceAll(',', '')) ?? 0;
        line.row = line.row.copyWith(amount: amount, unitPrice: price);
      }

      widget.controller.invoiceLines = _lines
          .where((l) => l.row.product.model.isNotEmpty && l.row.amount > 0)
          .map((l) => l.row)
          .toList();
      widget.controller.reCalculateTotal();
    });
  }

  void _markUnsaved() => widget.controller.hasUnsavedChanges = true;

  // ===== Helpers =====

  double? _getProductPrice(String model) {
    if (_priceCategory.name == null || _productsPricing == null) return null;
    return _productsPricing![model]?[_priceCategory.name]?.price;
  }

  String _formatNumber(num n) {
    final decimals = _priceCategory.currency == 'USD' ? 1 : 0;
    return NumberFormat.decimalPatternDigits(decimalDigits: decimals).format(n);
  }

  void _onPriceCategoryChanged((String, String?)? value) {
    if (value == null) return;
    setState(() {
      _priceCategory = (currency: value.$1, name: value.$2);
      for (final line in _lines) {
        if (line.row.product.model.isEmpty) continue;
        final newPrice = _getProductPrice(line.row.product.model);
        if (newPrice != null) {
          line.row = line.row.copyWith(unitPrice: newPrice);
          line.updatePrice(newPrice, _formatNumber);
        }
      }
    });
    _saveLines();
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Header(
          lineCount: _lines.length,
          priceCategory: _priceCategory,
          onCategoryChanged: _onPriceCategoryChanged,
        ),
        _buildDiscount(),
        _buildLinesList(),
        _buildAddButton(),
      ],
    );
  }

  Widget _buildDiscount() {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        spacing: 4,
        children: [
          const Icon(Icons.discount_outlined, color: Colors.redAccent),
          const Text('Discount: '),

          Flexible(
            child: _CustomTextField(
              label: 'Discount',
              onChanged: _updateDiscount,
              initialValue: widget.controller.discount.toString(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinesList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      itemCount: _lines.length,
      itemBuilder: (context, index) => _InvoiceLineCard(
        key: ValueKey(_lines[index].hashCode),
        index: index,
        lineData: _lines[index],
        products: _products,
        currency: _priceCategory.currency,
        formatNumber: _formatNumber,
        onRemove: () => _removeLine(index),
        onProductSelected: (name) => _updateProduct(index, name),
        onAmountChanged: (value) => _updateAmount(index, value),
        onPriceChanged: (value) => _updatePrice(index, value),
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextButton.icon(
        onPressed: _addLine,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add Line',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
    );
  }
}

// ===== Header Widget =====

class _Header extends StatelessWidget {
  const _Header({
    required this.lineCount,
    required this.priceCategory,
    required this.onCategoryChanged,
  });

  final int lineCount;
  final ({String currency, String? name}) priceCategory;
  final ValueChanged<(String, String?)?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long, color: colors.primary),
          const SizedBox(width: 8),
          Text(
            'Items ($lineCount)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          _buildDropdown(context),
        ],
      ),
    );
  }

  Widget _buildDropdown(BuildContext context) {
    return Futuristic(
      autoStart: true,
      futureBuilder: () => GetIt.I.get<PricingCategoryRepo>().getAll(),
      busyBuilder: (_) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      dataBuilder: (_, categories) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<(String, String?)>(
              isDense: true,
              value: (priceCategory.currency, priceCategory.name),
              style: context.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              items: [
                const DropdownMenuItem(
                  value: ('SP', null),
                  child: Text('Custom (ل.س)'),
                ),
                const DropdownMenuItem(
                  value: ('USD', null),
                  child: Text('Custom (\$)'),
                ),
                ...categories.map(
                  (e) => DropdownMenuItem(
                    value: (e.currency, e.name),
                    child: Text('${e.name} (${e.currency})'),
                  ),
                ),
              ],
              onChanged: onCategoryChanged,
            ),
          ),
        );
      },
    );
  }
}

// ===== Invoice Line Card =====

class _InvoiceLineCard extends StatelessWidget {
  const _InvoiceLineCard({
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

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                  child: _CustomTextField(
                    label: 'Qty',
                    controller: lineData.amountController,
                    onChanged: onAmountChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: _CustomTextField(
                    label: 'Price',
                    controller: lineData.priceController,
                    onChanged: onPriceChanged,
                    suffix: currency,
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

class _CustomTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final ValueChanged<String> onChanged;
  final String? suffix;
  final String? initialValue;

  const _CustomTextField({
    required this.label,
    required this.onChanged,
    this.controller,
    this.initialValue,
    this.suffix,
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
        suffixText: suffix,
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

// ===== Helper Widgets =====

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Total: '),
          Text(
            formatNumber(total),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colors.primary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ===== Extension =====

extension on InvoiceTableRow {
  InvoiceTableRow copyWith({num? unitPrice, int? amount, Product? product}) {
    return InvoiceTableRow(
      unitPrice: unitPrice ?? this.unitPrice,
      amount: amount ?? this.amount,
      product: product ?? this.product,
    );
  }
}
