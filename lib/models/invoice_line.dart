import 'package:i_gen/models/product.dart';

class InvoiceLine {
  final int invoiceId;
  final Product product;
  final int amount;
  final double price;

  InvoiceLine({
    required this.invoiceId,
    required this.product,
    required this.amount,
    required this.price,
  });
  double get lineTotal => amount * price;
  static InvoiceLine? fromMap(Map<String, dynamic> map) {
    if (map case {
      'invoice_id': int invoiceId,
      'product': Map<String, dynamic> product,
      'amount': double amount,
      'price': double price,
    }) {
      Product? prod = Product.fromMap(product);
      if (prod != null) {
        return InvoiceLine(
          invoiceId: invoiceId,
          product: prod,
          amount: amount.toInt(),
          price: price,
        );
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'invoice_id': invoiceId,
      'product': product.toMap(),
      'amount': amount,
      'price': price,
    };
  }
}
