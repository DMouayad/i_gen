import 'package:i_gen/models/invoice_line.dart';
import 'package:i_gen/models/product.dart';

class InvoiceTableRow {
  final num unitPrice;
  final int amount;
  final Product product;

  static InvoiceTableRow fromInvoiceLine(InvoiceLine line) {
    return InvoiceTableRow(
      unitPrice: line.price,
      amount: line.amount,
      product: line.product,
    );
  }

  InvoiceTableRow({
    required this.unitPrice,
    required this.amount,
    required this.product,
  });

  double get lineTotal => amount * unitPrice.toDouble();
}
