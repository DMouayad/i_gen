import 'package:i_gen/models/invoice_line.dart';
import 'package:i_gen/models/product.dart';

class InvoiceTableRow {
  final num unitPrice;
  final int amount;
  final Product product;

  /// Null = sizeless (stored as `''` — see [InvoiceLine.encodeSize]).
  final String? size;

  InvoiceTableRow({
    required this.unitPrice,
    required this.amount,
    required this.product,
    this.size,
  });

  static InvoiceTableRow fromInvoiceLine(InvoiceLine line) {
    return InvoiceTableRow(
      unitPrice: line.price,
      amount: line.amount,
      product: line.product,
      size: line.size,
    );
  }

  double get lineTotal => amount * unitPrice.toDouble();

  InvoiceTableRow copyWith({
    num? unitPrice,
    int? amount,
    Product? product,
    String? size,
  }) {
    return InvoiceTableRow(
      unitPrice: unitPrice ?? this.unitPrice,
      amount: amount ?? this.amount,
      product: product ?? this.product,
      size: size ?? this.size,
    );
  }
}
