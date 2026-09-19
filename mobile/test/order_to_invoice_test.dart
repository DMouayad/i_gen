import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/models/order.dart';
import 'package:i_gen/models/product.dart';

const _p1 = Product(id: 1, model: 'A1', name: 'Alpha');
const _p2 = Product(id: 2, model: 'B2', name: 'Beta');

OrderItem _item(String id, {String? model, int amount = 2, String size = ''}) {
  return OrderItem(
    id: id,
    orderId: 'o1',
    productId: 'server-$id',
    amount: amount,
    price: 0,
    productModel: model,
    size: size,
  );
}

void main() {
  test('matchOrderLines matches by model, carries size, counts skips', () {
    final byModel = {'A1': _p1, 'B2': _p2};
    final result = InvoiceDetailsController.matchOrderLines([
      _item('i1', model: 'A1', amount: 3, size: 'XL'),
      _item('i2', model: 'B2'),
      _item('i3', model: 'ZZZ'),
      _item('i4'),
    ], byModel);

    expect(result.rows, hasLength(2));
    expect(result.skipped, 2);
    expect(result.rows[0].product, _p1);
    expect(result.rows[0].amount, 3);
    expect(result.rows[0].size, 'XL');
    expect(result.rows[0].unitPrice, 0);
    expect(result.rows[1].size, isNull);
  });

  test('fromCustomerOrder prefills latched and unsaved', () {
    final matched = InvoiceDetailsController.matchOrderLines(
      [_item('i1', model: 'A1', amount: 3)],
      {'A1': _p1},
    );
    final controller = InvoiceDetailsController.fromCustomerOrder(
      customerName: 'Acme',
      currency: 'USD',
      lines: matched.rows,
      orderId: 'order-uuid-1',
    );

    expect(controller.customerName, 'Acme');
    expect(controller.orderId, 'order-uuid-1');
    expect(controller.invoiceLines, hasLength(1));
    expect(controller.cart.itemCount, 3);
    // Prefill is content: Save must persist even before further edits.
    expect(controller.hasUnsavedChanges, isTrue);
  });
}
