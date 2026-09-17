import 'package:i_gen/models/product.dart';

class InvoiceLine {
  final int invoiceId;
  final Product product;
  final int amount;
  final double price;
  final double discount;

  /// Null = sizeless. Stored as `''` (NOT NULL DEFAULT `''` keeps the
  /// UNIQUE-replace semantics for sizeless lines — NULLs are distinct).
  final String? size;

  InvoiceLine({
    required this.invoiceId,
    required this.product,
    required this.amount,
    required this.price,
    this.discount = 0.0,
    this.size,
  });
  double get lineTotal => amount * price * (1 - discount);

  static String encodeSize(String? size) => size ?? '';

  static String? decodeSize(Object? raw) {
    final s = raw as String?;
    return (s == null || s.isEmpty) ? null : s;
  }

  static InvoiceLine? fromMap(Map<String, dynamic> map) {
    if (map case {
      'invoice_id': int invoiceId,
      'product': Map<String, dynamic> product,
      'amount': int amount,
      'price': double price,
    }) {
      Product? prod = Product.fromMap(product);
      if (prod != null) {
        return InvoiceLine(
          invoiceId: invoiceId,
          product: prod,
          amount: amount,
          price: price,
          discount: map['discount'] ?? 0.0,
          size: decodeSize(map['size']),
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
      'discount': discount,
      'size': size,
    };
  }
}
