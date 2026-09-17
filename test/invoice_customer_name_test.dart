import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
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
}
