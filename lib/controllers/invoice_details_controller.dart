import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:i_gen/controllers/cart_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';

class InvoiceDetailsController {
  InvoiceDetailsController(this.invoice)
    : _invoiceDate = ValueNotifier(invoice?.date ?? DateTime.now()),
      _customerNameController = TextEditingController(
        text: invoice?.customerName,
      ),
      currency = invoice?.currency ?? 'USD',
      discount = invoice?.discount ?? 0,
      _enableEditing = ValueNotifier(invoice == null),
      invoiceId = invoice?.id,
      invoiceLines =
          invoice?.lines.map(InvoiceTableRow.fromInvoiceLine).toList() ?? [] {
    totalNotifier = ValueNotifier(_getTotal());
    // Seed the cart from the saved lines BEFORE the sync listener attaches,
    // so opening an existing invoice never latches unsaved state.
    for (final row in invoiceLines) {
      cart.add(
        row.product,
        size: row.size,
        price: row.unitPrice,
        qty: row.amount,
      );
    }
    cart.addListener(_syncLinesFromCart);
    // Init text is set above, before this listener attaches, so construction
    // itself never latches.
    _cleanCustomerName = _customerNameController.text;
    _customerNameController.addListener(() {
      if (_customerNameController.text != _cleanCustomerName) {
        _hasUnsavedChanges.value = true;
      }
    });
  }

  final ValueNotifier<int> textSizeNotifier = ValueNotifier(20);

  int? invoiceId;
  String currency;
  Invoice? invoice;
  final GlobalKey formKey = GlobalKey<FormState>();
  final ValueNotifier<DateTime> _invoiceDate;
  final TextEditingController _customerNameController;

  /// Name as last written to the db. Typing writes straight into
  /// [_customerNameController] (TypeAhead shares the instance) and bypasses
  /// the [customerName] setter, so the listener below — not the setter — is
  /// what latches unsaved state for keystrokes. Comparing against the clean
  /// copy keeps focus/selection noise from marking the invoice dirty.
  late String _cleanCustomerName;
  List<InvoiceTableRow> invoiceLines;

  /// Editor state for the cart UI (mobile grid + desktop). The single
  /// writer: every cart change rebuilds [invoiceLines] and the total below,
  /// so the desktop preview, `saveToDB`, and `hasUnsavedChanges` all follow
  /// without their own line bookkeeping.
  final CartController cart = CartController();
  final ValueNotifier<bool> _enableEditing;
  late final ValueNotifier<double> totalNotifier;
  double get total => totalNotifier.value;
  final ValueNotifier<bool> _hasUnsavedChanges = ValueNotifier(false);
  ValueNotifier<bool> get hasUnsavedChangesNotifier => _hasUnsavedChanges;

  bool get hasUnsavedChanges => _hasUnsavedChanges.value;
  double discount = 0;
  set hasUnsavedChanges(bool value) => _hasUnsavedChanges.value = value;

  ValueNotifier<DateTime> get invoiceDateNotifier => _invoiceDate;
  ValueNotifier<bool> get enableEditingNotifier => _enableEditing;

  /// Active price list. Screens observe this for the dropdown value and the
  /// grid; switching reprices every non-hand-edited cart line.
  final ValueNotifier<({String currency, String? name})> priceCategoryNotifier =
      ValueNotifier((currency: 'USD', name: null));

  ProductsPricing? _productsPricing;

  Future<void> loadPricing() async {
    _productsPricing = await GetIt.I
        .get<ProductPricingRepo>()
        .getProductsPricing();
    if (invoice?.currency case String currency) {
      priceCategoryNotifier.value = (currency: currency, name: null);
    }
  }

  double? priceOf(Product product) {
    final category = priceCategoryNotifier.value;
    if (category.name == null || _productsPricing == null) return null;
    return _productsPricing![product.model]?[category.name]?.price;
  }

  String formatNumber(num n) {
    final decimals = priceCategoryNotifier.value.currency == 'USD' ? 1 : 0;
    return NumberFormat.decimalPatternDigits(decimalDigits: decimals).format(n);
  }

  void switchPriceCategory((String, String?) value) {
    priceCategoryNotifier.value = (currency: value.$1, name: value.$2);
    cart.applyPrices(priceOf);
  }

  TextEditingController get customerNameController => _customerNameController;
  String get customerName => _customerNameController.text;

  set customerName(String value) {
    _customerNameController.text = value;
  }

  set enableEditing(bool value) => _enableEditing.value = value;
  bool get editingIsEnabled => _enableEditing.value;

  String getDate() {
    return '${_invoiceDate.value.year}-${_invoiceDate.value.month.toString().padLeft(2, '0')}-${_invoiceDate.value.day.toString().padLeft(2, '0')}';
  }

  Future<void> saveToDB({bool disableEditing = true}) async {
    if (disableEditing) {
      enableEditing = false;
    }
    if (hasUnsavedChanges) {
      invoice = await GetIt.I.get<InvoiceRepo>().insert(
        invoiceId: invoiceId,
        currency: currency,
        customerName: customerName,
        date: invoiceDateNotifier.value,
        discount: discount,
        total: totalNotifier.value,
        lines: invoiceLines,
      );
      invoiceId = invoice?.id;
      _cleanCustomerName = customerName;
    }
    hasUnsavedChanges = false;
  }

  void reCalculateTotal() {
    totalNotifier.value = _getTotal();
  }

  void _syncLinesFromCart() {
    invoiceLines = cart.lines
        .map(
          (l) => InvoiceTableRow(
            unitPrice: l.unitPrice,
            amount: l.qty,
            product: l.product,
            size: l.size,
          ),
        )
        .toList();
    totalNotifier.value = cart.total;
    _hasUnsavedChanges.value = true;
  }

  double _getTotal() {
    final lineTotals = invoiceLines.map((l) => l.lineTotal).toList();
    if (lineTotals.isNotEmpty) {
      return lineTotals.reduce((value, element) => value + element);
    }
    return 0;
  }
}
