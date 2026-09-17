import 'package:flutter/foundation.dart';

import 'package:i_gen/models/cart_line.dart';
import 'package:i_gen/models/product.dart';

class CartController extends ChangeNotifier {
  final _lines = <CartLine>[];
  List<CartLine> get lines => List.unmodifiable(_lines);

  int get itemCount => _lines.fold(0, (n, l) => n + l.qty);
  double get total => _lines.fold(0, (n, l) => n + l.total);
  bool get isEmpty => _lines.isEmpty;

  CartLine? _find(Product p, String? size) {
    for (final l in _lines) {
      if (l.product.id == p.id && l.size == size) return l;
    }
    return null;
  }

  int qtyOf(Product p) =>
      _lines.where((l) => l.product.id == p.id).fold(0, (n, l) => n + l.qty);

  int qtyOfSize(Product p, String size) => _find(p, size)?.qty ?? 0;

  void add(Product product, {String? size, num? price, int qty = 1}) {
    final line = _find(product, size);
    if (line != null) {
      line.qty += qty;
    } else {
      _lines.add(
        CartLine(product: product, size: size, unitPrice: price ?? 0, qty: qty),
      );
    }
    notifyListeners();
  }

  void setQty(CartLine line, int qty) {
    if (qty <= 0) {
      // Minus/X deletes; typing in the field never does.
      _lines.remove(line);
    } else {
      line.qty = qty;
    }
    notifyListeners();
  }

  void setPrice(CartLine line, num price) {
    line.unitPrice = price;
    line.priceOverridden = true;
    notifyListeners();
  }

  /// Moving a line to another size merges into an existing line if present.
  void setSize(CartLine line, String? size) {
    if (line.size == size) return;
    final target = _find(line.product, size);
    if (target != null) {
      target.qty += line.qty;
      _lines.remove(line);
    } else {
      line.size = size;
    }
    notifyListeners();
  }

  void remove(CartLine line) {
    _lines.remove(line);
    notifyListeners();
  }

  /// Price-list switch: only reprices lines the user hasn't hand-edited.
  void applyPrices(num? Function(Product) priceOf) {
    for (final l in _lines) {
      if (l.priceOverridden) continue;
      final p = priceOf(l.product);
      if (p != null) l.unitPrice = p;
    }
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
