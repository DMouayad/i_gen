import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:get_it/get_it.dart';

import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/utils/futuristic.dart';
import 'package:i_gen/widgets/custom_text_field.dart';
import 'package:i_gen/widgets/invoice_line_card.dart';

import 'prevent_pop.dart';

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

class InvoiceDetailsMobile extends StatefulWidget {
  const InvoiceDetailsMobile({
    super.key,
    required this.controller,
    this.onSaved,
  });
  final InvoiceDetailsController controller;
  final void Function(Invoice invoice)? onSaved;

  @override
  State<InvoiceDetailsMobile> createState() => _InvoiceDetailsMobileState();
}

class _InvoiceDetailsMobileState extends State<InvoiceDetailsMobile> {
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
      _lines[index].updatePrice(
        newPrice,
        widget.controller.formatNumberForCurrency,
      );
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

  void _onPriceCategoryChanged((String, String?)? value) {
    if (value == null) return;
    setState(() {
      _priceCategory = (currency: value.$1, name: value.$2);
      for (final line in _lines) {
        if (line.row.product.model.isEmpty) continue;
        final newPrice = _getProductPrice(line.row.product.model);
        if (newPrice != null) {
          line.row = line.row.copyWith(unitPrice: newPrice);
          line.updatePrice(newPrice, widget.controller.formatNumberForCurrency);
        }
      }
    });
    _saveLines();
  }

  Future<void> _onSave() async {
    await widget.controller.saveToDB();
    if (widget.controller.invoice != null) {
      widget.onSaved?.call(widget.controller.invoice!);
    }
  }

  // ===== UI =====

  @override
  Widget build(BuildContext context) {
    final btnTextStyle = context.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return PreventPop(
      controller: widget.controller,
      child: Scaffold(
        appBar: AppBar(
          title: widget.controller.invoice == null
              ? const Text('New invoice')
              : null,
          actions: [
            TextButton.icon(
              onPressed: _onSave,
              icon: const Icon(Icons.save, size: 22),
              label: Text('Save', style: btnTextStyle),
            ),
            TextButton.icon(
              onPressed: () async {
                await _onSave();
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          InvoiceDetails(invoiceController: widget.controller),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.send, size: 22),
              label: Text('Export', style: btnTextStyle),
            ),
          ],
        ),
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ValueListenableBuilder(
                valueListenable: widget.controller.discountNotifier,
                builder: (context, discount, child) {
                  return ValueListenableBuilder(
                    valueListenable: widget.controller.totalNotifier,
                    builder: (context, total, _) {
                      return Text(
                        'Grand total: ${widget.controller.formatNumberForCurrency(total - discount)}',
                        style: context.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  );
                },
              ),
              TextButton.icon(
                onPressed: _addLine,
                icon: const Icon(Icons.add),
                label: const Text(
                  'Add item',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        body: Center(
          heightFactor: 1,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8),
            width: 430,
            child: SingleChildScrollView(
              child: Column(
                spacing: 10,
                children: [
                  const SizedBox(height: 1),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: _cardColor(context),
                    onTap: () async {
                      final newDate = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2025),
                        lastDate: DateTime(2050),
                      );
                      if (newDate != null) {
                        widget.controller.invoiceDateNotifier.value = newDate;
                      }
                    },
                    trailing: const Icon(Icons.edit),
                    leading: Icon(
                      Icons.calendar_today_outlined,
                      color: context.colorScheme.primary,
                    ),
                    title: ValueListenableBuilder(
                      valueListenable: widget.controller.invoiceDateNotifier,
                      builder: (context, value, _) {
                        return Text(
                          widget.controller.getDate(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    children: [
                      Icon(Icons.person, color: context.colorScheme.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: TypeAheadField<String>(
                          controller: widget.controller.customerNameController,
                          itemBuilder: (context, value) => ListTile(
                            title: Text(
                              value,
                              style: context.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            tileColor: context.colorScheme.surface,
                          ),
                          onSelected: (value) {
                            widget.controller.customerName = value;
                          },
                          builder: (context, textController, focusNode) {
                            return TextFormField(
                              controller: textController,
                              focusNode: focusNode,
                              textAlign: TextAlign.center,
                              onFieldSubmitted: (value) {
                                widget.controller.customerName = value;
                              },
                              style: context.defaultTextStyle.copyWith(
                                fontSize: 20,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Customer name',
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    width: 1,
                                    color: context.colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    width: 2,
                                    color: context.colorScheme.primary,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            );
                          },
                          hideOnSelect: true,
                          hideOnEmpty: true,
                          suggestionsCallback: (query) =>
                              GetIt.I.get<CustomerRepo>().search(query),
                        ),
                      ),
                    ],
                  ),
                  _wrapWithCard(
                    Column(
                      spacing: 16,
                      children: [
                        _Header(
                          priceCategory: _priceCategory,
                          onCategoryChanged: _onPriceCategoryChanged,
                        ),
                        _buildDiscount(),
                      ],
                    ),
                  ),

                  _buildLinesList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _cardColor(BuildContext context) {
    return context.colorScheme.surfaceContainerHighest.withOpacity(0.5);
  }

  Widget _wrapWithCard(Widget child) {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _cardColor(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _buildDiscount() {
    return Row(
      spacing: 8,
      children: [
        const Icon(Icons.discount_outlined, color: Colors.redAccent),
        Flexible(
          child: CustomTextField(
            label: 'Discount',
            onChanged: _updateDiscount,
            initialValue: widget.controller.discount.toString(),
          ),
        ),
      ],
    );
  }

  Widget _buildLinesList() {
    return _wrapWithCard(
      Column(
        spacing: 10,
        children: [
          Row(
            spacing: 8,
            children: [
              Icon(Icons.receipt_long, color: context.colorScheme.primary),
              Text(
                'Items (${_lines.length})',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _lines.length,
            itemBuilder: (context, index) => InvoiceLineCard(
              key: ValueKey(_lines[index].hashCode),
              index: index,
              lineData: _lines[index],
              products: _products,
              currency: _priceCategory.currency,
              formatNumber: widget.controller.formatNumberForCurrency,
              onRemove: () => _removeLine(index),
              onProductSelected: (name) => _updateProduct(index, name),
              onAmountChanged: (value) => _updateAmount(index, value),
              onPriceChanged: (value) => _updatePrice(index, value),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Header Widget =====

class _Header extends StatelessWidget {
  const _Header({required this.priceCategory, required this.onCategoryChanged});

  final ({String currency, String? name}) priceCategory;
  final ValueChanged<(String, String?)?> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      spacing: 8,
      children: [
        Icon(Icons.currency_exchange, color: colors.primary),
        Text(
          'Pricing',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const Spacer(),
        _buildDropdown(context),
      ],
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
