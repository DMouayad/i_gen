import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:i_gen/controllers/cart_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/order.dart';
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
          invoice?.lines.map(InvoiceTableRow.fromInvoiceLine).toList() ?? [],
      orderId = invoice?.orderId {
    _initCartAndListeners();
  }

  final ValueNotifier<int> textSizeNotifier = ValueNotifier(20);

  int? invoiceId;
  String currency;
  Invoice? invoice;

  /// Server order uuid this invoice was made from (null = manual invoice).
  /// Set once at prefill, then carried through every save.
  String? orderId;
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
        // Origin rides along on creation; updates preserve the stored one
        // (the repo never rewrites it).
        orderId: orderId ?? invoice?.orderId,
      );
      invoiceId = invoice?.id;
      _cleanCustomerName = customerName;
    }
    hasUnsavedChanges = false;
  }

  void reCalculateTotal() {
    totalNotifier.value = _getTotal();
  }

  /// Prefilled new invoice from a customer order (no [Invoice] yet).
  /// Prices stay 0 (customers order blind) and the category stays custom,
  /// so staff price it like any new invoice. Latched unsaved: the prefill is
  /// content, so Save must persist even before further edits.
  InvoiceDetailsController.fromCustomerOrder({
    required String customerName,
    required String currency,
    required List<InvoiceTableRow> lines,
    required this.orderId,
  }) : _invoiceDate = ValueNotifier(DateTime.now()),
       _customerNameController = TextEditingController(text: customerName),
       currency = currency,
       discount = 0,
       _enableEditing = ValueNotifier(true),
       invoiceId = null,
       invoice = null,
       invoiceLines = List.of(lines) {
    priceCategoryNotifier.value = (currency: currency, name: null);
    _initCartAndListeners();
    _hasUnsavedChanges.value = true;
  }

  /// Matches customer-order lines to local products by model (natural
  /// key, same rule as catalog sync convergence). Prices stay 0 — the web
  /// app orders blind — and sizes carry over. Returns matched rows plus a
  /// skipped count (unknown/deleted products); skips are counted, never
  /// silent, so the caller can report them.
  static ({List<InvoiceTableRow> rows, int skipped}) matchOrderLines(
    List<OrderItem> items,
    Map<String, Product> productsByModel,
  ) {
    final rows = <InvoiceTableRow>[];
    var skipped = 0;
    for (final item in items) {
      final product = productsByModel[item.productModel ?? ''];
      if (product == null) {
        skipped++;
        continue;
      }
      rows.add(
        InvoiceTableRow(
          unitPrice: 0,
          amount: item.amount,
          product: product,
          size: item.size.isEmpty ? null : item.size,
        ),
      );
    }
    return (rows: rows, skipped: skipped);
  }

  void _initCartAndListeners() {
    totalNotifier = ValueNotifier(_getTotal());
    // Seed the cart from the lines BEFORE the sync listener attaches,
    // so opening never latches unsaved state by itself.
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
