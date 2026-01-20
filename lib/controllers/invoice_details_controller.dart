import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/repos/invoice_repo.dart';

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
  }

  final ValueNotifier<int> textSizeNotifier = ValueNotifier(20);

  int? invoiceId;
  String currency;
  Invoice? invoice;
  final GlobalKey formKey = GlobalKey<FormState>();
  final ValueNotifier<DateTime> _invoiceDate;
  final TextEditingController _customerNameController;
  List<InvoiceTableRow> invoiceLines;
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

  TextEditingController get customerNameController => _customerNameController;
  String get customerName => _customerNameController.text;

  set customerName(String value) {
    _customerNameController.text = value;
    _hasUnsavedChanges.value = true;
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
      final invoice = await GetIt.I.get<InvoiceRepo>().insert(
        invoiceId: invoiceId,
        currency: currency,
        customerName: customerName,
        date: invoiceDateNotifier.value,
        discount: discount,
        total: totalNotifier.value,
        lines: invoiceLines,
      );
      invoiceId = invoice.id;
    }
    hasUnsavedChanges = false;
  }

  void reCalculateTotal() {
    totalNotifier.value = _getTotal();
  }

  double _getTotal() {
    final lineTotals = invoiceLines.map((l) => l.lineTotal).toList();
    if (lineTotals.isNotEmpty) {
      return lineTotals.reduce((value, element) => value + element);
    }
    return 0;
  }
}
