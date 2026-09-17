import 'package:flutter_test/flutter_test.dart';

import 'package:i_gen/controllers/cart_controller.dart';
import 'package:i_gen/models/product.dart';

const _a = Product(id: 1, model: 'A1', name: 'a-one', sizes: ['S', 'M']);
const _b = Product(id: 2, model: 'B1', name: 'b-one');

void main() {
  test('add merges same product+size, splits sizes', () {
    final cart = CartController();
    cart.add(_a, size: 'S', price: 10);
    cart.add(_a, size: 'S', price: 10, qty: 2);
    cart.add(_a, size: 'M', price: 10);
    cart.add(_a, price: 10); // sizeless line is distinct from sized ones
    expect(cart.lines, hasLength(3));
    expect(cart.qtyOfSize(_a, 'S'), 3);
    expect(cart.qtyOf(_a), 5);
    expect(cart.total, 50);
  });

  test('sizeless product adds one line; qty accumulates', () {
    final cart = CartController();
    cart.add(_b, size: _b.singleSize, price: 7);
    cart.add(_b, size: _b.singleSize, price: 7);
    expect(cart.lines, hasLength(1));
    expect(cart.itemCount, 2);
    expect(cart.total, 14);
  });

  test('setQty zero removes the line', () {
    final cart = CartController();
    cart.add(_b, price: 7, qty: 2);
    final line = cart.lines.single;
    cart.setQty(line, 0);
    expect(cart.isEmpty, isTrue);
  });

  test('setSize merges into an existing line', () {
    final cart = CartController();
    cart.add(_a, size: 'S', price: 10, qty: 2);
    cart.add(_a, size: 'M', price: 10, qty: 3);
    final sLine = cart.lines.firstWhere((l) => l.size == 'S');
    cart.setSize(sLine, 'M');
    expect(cart.lines, hasLength(1));
    expect(cart.qtyOfSize(_a, 'M'), 5);
  });

  test('setSize to a free size just moves', () {
    final cart = CartController();
    cart.add(_a, size: 'S', price: 10, qty: 2);
    cart.setSize(cart.lines.single, 'M');
    expect(cart.lines.single.size, 'M');
    expect(cart.qtyOfSize(_a, 'M'), 2);
  });

  test('applyPrices skips hand-edited lines', () {
    final cart = CartController();
    cart.add(_a, size: 'S', price: 10);
    cart.add(_a, size: 'M', price: 10);
    cart.setPrice(cart.lines.first, 99);
    cart.applyPrices((_) => 20);
    expect(cart.lines.first.unitPrice, 99);
    expect(cart.lines.last.unitPrice, 20);
  });

  test('remove and clear', () {
    final cart = CartController();
    cart.add(_a, size: 'S', price: 10);
    cart.add(_b, price: 7);
    cart.remove(cart.lines.first);
    expect(cart.lines, hasLength(1));
    cart.clear();
    expect(cart.isEmpty, isTrue);
    expect(cart.total, 0);
  });
}
