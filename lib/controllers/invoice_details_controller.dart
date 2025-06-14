import 'package:flutter/widgets.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/invoice_table_row.dart';

class InvoiceDetailsController {
  InvoiceDetailsController(this.invoice)
    : _invoiceDate = ValueNotifier(invoice?.date ?? DateTime.now()),
      _customerNameController = TextEditingController(
        text: invoice?.customerName,
      ),
      discount = invoice?.discount ?? 0,
      _enableEditing = ValueNotifier(invoice == null),
      invoiceId = invoice?.id,
      invoiceLines =
          invoice?.lines.map(InvoiceTableRow.fromInvoiceLine).toList() ?? [];

  final ValueNotifier<int> textSizeNotifier = ValueNotifier(18);

  int? invoiceId;
  Invoice? invoice;
  final GlobalKey formKey = GlobalKey<FormState>();
  final ValueNotifier<DateTime> _invoiceDate;
  final TextEditingController _customerNameController;
  List<InvoiceTableRow> invoiceLines;
  final ValueNotifier<bool> _enableEditing;
  final ValueNotifier<bool> _hasUnsavedChanges = ValueNotifier(false);
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
}
