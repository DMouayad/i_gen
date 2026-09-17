import 'package:i_gen/models/product.dart';

class CartLine {
  CartLine({
    required this.product,
    this.size,
    required this.unitPrice,
    this.qty = 1,
  });

  final Product product;
  String? size;
  num unitPrice;
  int qty;

  /// Typed by hand → survives price-list switches.
  bool priceOverridden = false;

  double get total => qty * unitPrice.toDouble();
}
