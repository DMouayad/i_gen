import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/utils/futuristic.dart';
import 'package:intl/intl.dart';

class InvoiceLineInputMobile extends StatefulWidget {
  const InvoiceLineInputMobile({super.key, required this.controller});
  final InvoiceDetailsController controller;

  @override
  State<InvoiceLineInputMobile> createState() => _InvoiceLineInputMobileState();
}

class _InvoiceLineInputMobileState extends State<InvoiceLineInputMobile> {
  late List<InvoiceTableRow> _invoiceRows;
  ProductsPricing? _productsPricing;
  ({String? name, String currency}) _selectedPriceCategory = (
    currency: 'USD',
    name: null,
  );
  final products = GetIt.I.get<ProductsController>().products;

  final List<TextEditingController> _amountControllers = [];
  final List<TextEditingController> _priceControllers = [];

  @override
  void initState() {
    super.initState();
    _invoiceRows = List.from(widget.controller.invoiceLines);
    if (_invoiceRows.isEmpty) {
      _invoiceRows.add(_newEmptyRow());
    }
    _initializeControllers();
    _fetchInitialData();

    widget.controller.enableEditingNotifier.addListener(_onEditingToggle);
  }

  @override
  void dispose() {
    widget.controller.enableEditingNotifier.removeListener(_onEditingToggle);
    _clearControllers();
    super.dispose();
  }

  void _initializeControllers() {
    _clearControllers();
    for (var row in _invoiceRows) {
      _addControllersForRow(row);
    }
  }

  void _addControllersForRow(InvoiceTableRow row) {
    final amountController = TextEditingController(
      text: row.amount == 0 ? '' : row.amount.toString(),
    );
    final priceController = TextEditingController(
      text: row.unitPrice == 0
          ? ''
          : _formatNumber(row.unitPrice, decimal: true),
    );

    _amountControllers.add(amountController);
    _priceControllers.add(priceController);
  }

  void _clearControllers() {
    for (var controller in _amountControllers) {
      controller.dispose();
    }
    for (var controller in _priceControllers) {
      controller.dispose();
    }
    _amountControllers.clear();
    _priceControllers.clear();
  }

  void _onEditingToggle() {
    if (!widget.controller.editingIsEnabled) {
      _saveInvoiceLines();
    }
  }

  Future<void> _fetchInitialData() async {
    _productsPricing = await GetIt.I
        .get<ProductPricingRepo>()
        .getProductsPricing();
    if (widget.controller.invoice?.currency case String currency) {
      _selectedPriceCategory = (currency: currency, name: null);
    }
    if (mounted) {
      setState(() {}); // Rebuild to display fetched data
    }
  }

  InvoiceTableRow _newEmptyRow() {
    return InvoiceTableRow(
      unitPrice: 0,
      amount: 0,
      product: Product(id: -1, model: '', name: ''), // Placeholder product
    );
  }

  void _addInvoiceLine() {
    setState(() {
      final newRow = _newEmptyRow();
      _invoiceRows.add(newRow);
      _addControllersForRow(newRow);
      widget.controller.hasUnsavedChanges = true;
    });
  }

  void _removeInvoiceLine(int index) {
    setState(() {
      // Dispose and remove controllers
      _amountControllers[index].dispose();
      _priceControllers[index].dispose();
      _amountControllers.removeAt(index);
      _priceControllers.removeAt(index);

      // Remove row
      _invoiceRows.removeAt(index);
      widget.controller.hasUnsavedChanges = true;

      // Add an empty row if the list becomes empty
      if (_invoiceRows.isEmpty) {
        _addInvoiceLine();
      }
    });
  }

  void _updateProduct(int index, String? newModel) {
    if (newModel == null) return;
    setState(() {
      final product = products[newModel];
      if (product != null) {
        final currentLine = _invoiceRows[index];
        final newUnitPrice = _getModelPriceByCategory(
          product.model,
          _selectedPriceCategory.name,
        );

        _invoiceRows[index] = currentLine.copyWith(
          product: product,
          unitPrice: newUnitPrice ?? 0,
        );

        // Update the price controller's text
        final formattedPrice = (newUnitPrice == null || newUnitPrice == 0)
            ? ''
            : _formatNumber(newUnitPrice);
        _priceControllers[index].text = formattedPrice;

        widget.controller.hasUnsavedChanges = true;
      }
    });
  }

  void _updateAmount(int index, String value) {
    final int? amount = int.tryParse(value);
    if (amount != null && amount >= 0 && _invoiceRows[index].amount != amount) {
      setState(() {
        _invoiceRows[index] = _invoiceRows[index].copyWith(amount: amount);
        widget.controller.hasUnsavedChanges = true;
      });
    }
  }

  void _updateUnitPrice(int index, String value) {
    final unitPrice = num.tryParse(value);

    if (unitPrice != null &&
        unitPrice >= 0 &&
        _invoiceRows[index].unitPrice != unitPrice) {
      setState(() {
        _invoiceRows[index] = _invoiceRows[index].copyWith(
          unitPrice: unitPrice,
        );
        widget.controller.hasUnsavedChanges = true;
      });
    }
  }

  double? _getModelPriceByCategory(String? model, String? pricingCategory) {
    if (model == null || pricingCategory == null || _productsPricing == null) {
      return null;
    }
    return _productsPricing![model]?[pricingCategory]?.price;
  }

  String _formatNumber(num n, {bool decimal = true}) {
    return switch (_selectedPriceCategory.currency) {
      'SP' => NumberFormat.decimalPatternDigits(decimalDigits: 0).format(n),
      'USD' => NumberFormat.decimalPatternDigits(
        decimalDigits: decimal ? 2 : 0,
      ).format(n),
      _ => NumberFormat.decimalPatternDigits(decimalDigits: 0).format(n),
    };
  }

  void _saveInvoiceLines() {
    // First, ensure the internal state `_invoiceRows` is up-to-date with controllers
    for (int i = 0; i < _invoiceRows.length; i++) {
      final amount = int.tryParse(_amountControllers[i].text) ?? 0;
      final price = num.tryParse(_priceControllers[i].text) ?? 0.0;
      if (_invoiceRows[i].amount != amount ||
          _invoiceRows[i].unitPrice != price) {
        _invoiceRows[i] = _invoiceRows[i].copyWith(
          amount: amount,
          unitPrice: price,
        );
      }
    }

    final validInvoiceLines = _invoiceRows.where(
      (row) =>
          row.product.model.isNotEmpty && row.amount > 0 && row.unitPrice >= 0,
    );

    widget.controller.invoiceLines = validInvoiceLines.toList();
    widget.controller.hasUnsavedChanges = false;
  }

  void _onPriceCategoryChanged((String, String?)? newValue) {
    if (newValue == null) return;
    setState(() {
      _selectedPriceCategory = (currency: newValue.$1, name: newValue.$2);
      // Update unit prices for all existing lines
      for (int i = 0; i < _invoiceRows.length; i++) {
        final currentLine = _invoiceRows[i];
        if (currentLine.product.model.isEmpty) continue;

        final newUnitPrice = _getModelPriceByCategory(
          currentLine.product.model,
          _selectedPriceCategory.name,
        );
        _invoiceRows[i] = currentLine.copyWith(
          unitPrice: newUnitPrice ?? currentLine.unitPrice,
        );

        // Update controller
        final priceToShow = newUnitPrice ?? currentLine.unitPrice;
        _priceControllers[i].text = priceToShow == 0
            ? ''
            : _formatNumber(priceToShow, decimal: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        _buildInvoiceLinesList(),
        _buildAddLineButton(),
      ],
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Invoice Lines',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Futuristic(
            autoStart: true,
            futureBuilder: () => GetIt.I.get<PricingCategoryRepo>().getAll(),
            dataBuilder: (context, categories) {
              return DropdownButtonHideUnderline(
                child: DropdownButton<(String, String?)>(
                  isDense: true,
                  iconSize: 20,
                  value: (
                    _selectedPriceCategory.currency,
                    _selectedPriceCategory.name,
                  ),
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  hint: const Text('Select price list'),
                  items: [
                    const DropdownMenuItem(
                      value: ('SP', null),
                      child: Text('Custom ل.س'),
                    ),
                    const DropdownMenuItem(
                      value: ('USD', null),
                      child: Text('Custom \$(USD)'),
                    ),
                    ...categories.map(
                      (e) => DropdownMenuItem(
                        value: (e.currency, e.name),
                        child: Text(
                          '${e.name} (${e.currency})',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                  onChanged: widget.controller.editingIsEnabled
                      ? _onPriceCategoryChanged
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceLinesList() {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _invoiceRows.length,
      itemBuilder: (context, index) {
        final row = _invoiceRows[index];
        return _InvoiceLineCard(
          row: row,
          index: index,
          amountController: _amountControllers[index],
          priceController: _priceControllers[index],
          products: products,
          editingIsEnabled: widget.controller.editingIsEnabled,
          onRemoveLine: _removeInvoiceLine,
          onUpdateProduct: _updateProduct,
          onUpdateAmount: _updateAmount,
          onUpdateUnitPrice: _updateUnitPrice,
          formatNumber: _formatNumber,
        );
      },
    );
  }

  Widget _buildAddLineButton() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextButton.icon(
        onPressed: _addInvoiceLine,
        icon: const Icon(Icons.add),
        label: const Text('Add Line'),
      ),
    );
  }
} // This is the closing brace for the _InvoiceLineInputMobileState class.

class _InvoiceLineCard extends StatelessWidget {
  const _InvoiceLineCard({
    required this.row,
    required this.index,
    required this.amountController,
    required this.priceController,
    required this.products,
    required this.editingIsEnabled,
    required this.onRemoveLine,
    required this.onUpdateProduct,
    required this.onUpdateAmount,
    required this.onUpdateUnitPrice,
    required this.formatNumber,
  });

  final InvoiceTableRow row;
  final int index;
  final TextEditingController amountController;
  final TextEditingController priceController;
  final Map<String, Product> products;
  final bool editingIsEnabled;
  final void Function(int) onRemoveLine;
  final void Function(int, String?) onUpdateProduct;
  final void Function(int, String) onUpdateAmount;
  final void Function(int, String) onUpdateUnitPrice;
  final String Function(num, {bool decimal}) formatNumber;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TypeAheadField<String>(
                    builder: (context, controller, focusNode) => TextFormField(
                      initialValue: row.product.name,
                      focusNode: focusNode,
                      textAlign: TextAlign.center,
                      onChanged: (v) => controller.text = v,
                      decoration: const InputDecoration(
                        hint: Text('Select Product'),
                        labelText: 'Product',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    onSelected: (value) => onUpdateProduct(index, value),
                    itemBuilder: (context, value) =>
                        ListTile(dense: true, title: Text(value)),
                    suggestionsCallback: (q) => products.values
                        .where((p) => p.name.contains(q) || p.model.contains(q))
                        .map((e) => e.name)
                        .toList(),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                  onPressed: () => onRemoveLine(index),
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) => onUpdateAmount(index, value),
                    readOnly: !editingIsEnabled,
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: TextFormField(
                    controller: priceController,
                    decoration: const InputDecoration(
                      labelText: 'Unit Price',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (value) => onUpdateUnitPrice(index, value),
                    readOnly: !editingIsEnabled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Line Total: ${formatNumber(row.lineTotal)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on InvoiceTableRow {
  InvoiceTableRow copyWith({num? unitPrice, int? amount, Product? product}) {
    return InvoiceTableRow(
      unitPrice: unitPrice ?? this.unitPrice,
      amount: amount ?? this.amount,
      product: product ?? this.product,
    );
  }
}
