import 'package:flutter/material.dart';
import 'package:i_gen/models/invoice.dart';

class InvoicesController extends ChangeNotifier {
  Map<int, Invoice> _value = {};

  InvoicesController();

  List<Invoice> get invoices => _value.values.toList(growable: false);

  void removeInvoice(Invoice invoice) {
    final newList = _value.values.toList();
    newList.remove(invoice);
    update(newList);
  }

  void update(Iterable<Invoice> invoices) {
    _value = Map.fromEntries(invoices.map((i) => MapEntry(i.id, i)));
    notifyListeners();
  }

  void addNewInvoice(Invoice invoice) {
    final newList = _value.values.toList();
    newList.add(invoice);
    update(newList);
  }

  void updateInvoice(Invoice invoice) {
    _value[invoice.id] = invoice;
    update(_value.values);
  }
}
