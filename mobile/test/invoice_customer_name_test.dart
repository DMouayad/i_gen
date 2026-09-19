import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helper.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await openFreshTestDb();
    await GetIt.I.reset();
    GetIt.I.registerSingleton(ProductsController(products: const []));
    GetIt.I.registerSingleton(InvoiceRepo(db));
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  test('typing a name latches unsaved (setter bypass covered)', () {
    final controller = InvoiceDetailsController(null);
    expect(controller.hasUnsavedChanges, isFalse);

    // What TypeAhead typing does: writes straight into the controller.
    controller.customerNameController.text = 'Acme';
    expect(controller.hasUnsavedChanges, isTrue);
    expect(controller.customerName, 'Acme');
  });

  test('name-only new invoice saves with the name', () async {
    final controller = InvoiceDetailsController(null);
    controller.customerNameController.text = 'Acme';

    await controller.saveToDB();

    expect(controller.invoice?.customerName, 'Acme');
    final stored = await db.query(
      DbConstants.tableInvoice,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [controller.invoiceId],
    );
    expect(stored, hasLength(1));
    expect(stored.single[DbConstants.columnCustomerName], 'Acme');
  });

  test('re-selecting the saved name does not latch', () async {
    final controller = InvoiceDetailsController(null);
    controller.customerNameController.text = 'Acme';
    await controller.saveToDB();
    expect(controller.hasUnsavedChanges, isFalse);

    controller.customerName = 'Acme';
    expect(controller.hasUnsavedChanges, isFalse);
  });

  test('renaming an existing invoice persists on save', () async {
    final first = InvoiceDetailsController(null);
    first.customerNameController.text = 'Acme';
    await first.saveToDB();

    final stored = await InvoiceRepo(db).getInvoices();
    final reopened = InvoiceDetailsController(stored.single);
    expect(reopened.hasUnsavedChanges, isFalse);

    reopened.customerNameController.text = 'Globex';
    expect(reopened.hasUnsavedChanges, isTrue);
    await reopened.saveToDB();

    final again = await InvoiceRepo(db).getInvoices();
    expect(again.single.customerName, 'Globex');
  });

  test('order origin persists, marks invoiced, survives updates', () async {
    final controller = InvoiceDetailsController.fromCustomerOrder(
      customerName: 'Acme',
      currency: 'USD',
      lines: const [],
      orderId: 'order-1',
    );
    await controller.saveToDB();
    expect(controller.invoice?.orderId, 'order-1');

    final stored = await InvoiceRepo(db).getInvoices();
    expect(stored.single.orderId, 'order-1');
    expect(await InvoiceRepo(db).getInvoicedOrderIds(), {'order-1'});

    // Manual invoices stay unmarked.
    final manual = InvoiceDetailsController(null);
    manual.customerNameController.text = 'Other';
    await manual.saveToDB();
    expect(await InvoiceRepo(db).getInvoicedOrderIds(), {'order-1'});

    // Updates preserve the origin (never rewritten).
    controller.customerNameController.text = 'Acme Corp';
    await controller.saveToDB();
    final again = await InvoiceRepo(db).getInvoices();
    expect(
      again.firstWhere((i) => i.id == controller.invoice!.id).orderId,
      'order-1',
    );
  });

  test('Invoice.fromMap reads a missing order_id as null', () {
    final invoice = Invoice.fromMap({
      '_id': 1,
      'customer': 'Acme',
      'date': DateTime(2026, 1, 1).toIso8601String(),
      'total': 0.0,
      'discount': 0.0,
      'currency': 'USD',
    });
    expect(invoice?.orderId, isNull);
  });

  test('discount set on the controller persists end to end', () async {
    final controller = InvoiceDetailsController(null);
    controller.customerNameController.text = 'Acme';
    // What the footer onChanged does.
    controller.discount = 10.5;
    controller.hasUnsavedChanges = true;

    await controller.saveToDB();
    expect(controller.invoice?.discount, 10.5);

    final stored = await InvoiceRepo(db).getInvoices();
    expect(stored.single.discount, 10.5);

    // And it redisplays when the invoice is reopened.
    final reopened = InvoiceDetailsController(stored.single);
    expect(reopened.discount, 10.5);
  });

  test('order-invoice map points at the newest link, singles by id', () async {
    Future<InvoiceDetailsController> savedOrderInvoice(String order) async {
      final c = InvoiceDetailsController.fromCustomerOrder(
        customerName: 'Acme',
        currency: 'USD',
        lines: const [],
        orderId: order,
      );
      await c.saveToDB();
      return c;
    }

    final first = await savedOrderInvoice('order-1');
    await savedOrderInvoice('order-1');
    await savedOrderInvoice('order-2');

    final repo = InvoiceRepo(db);
    expect(await repo.getOrderInvoiceMap(), {
      'order-1': first.invoice!.id + 1,
      'order-2': first.invoice!.id + 2,
    });

    final opened = await repo.getInvoiceById(first.invoice!.id + 1);
    expect(opened?.orderId, 'order-1');
    expect(await repo.getInvoiceById(999999), isNull);
  });
}
