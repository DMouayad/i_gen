import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helper.dart';

void main() {
  late Database db;
  late InvoiceRepo invoices;
  late ProductRepo products;
  late CustomerRepo customers;

  setUp(() async {
    db = await openFreshTestDb();
    invoices = InvoiceRepo(db);
    products = ProductRepo(db);
    customers = CustomerRepo(db);
    await GetIt.I.reset();
    GetIt.I.registerSingleton(ProductsController(products: const []));
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  Future<void> registerProducts(List<Product> list) async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton(ProductsController(products: list));
  }

  test('insert enqueues one op per row atomically', () async {
    final p1 = await products.insertProduct(model: 'P1', name: 'p1');
    final p2 = await products.insertProduct(model: 'P2', name: 'p2');
    await registerProducts([p1, p2]);
    final before = (await outboxRows(db)).length;

    final invoice = await invoices.insert(
      customerName: 'Acme',
      currency: 'USD',
      date: DateTime(2026, 1, 2),
      total: 30,
      discount: 0,
      lines: [
        InvoiceTableRow(product: p1, amount: 1, unitPrice: 10),
        InvoiceTableRow(product: p2, amount: 2, unitPrice: 10),
      ],
    );

    final ops = await outboxRows(db);
    final mine = ops.skip(before).toList();
    expect(mine, hasLength(3));
    expect(
      mine.where(
        (o) =>
            o[DbConstants.columnTableName] == DbConstants.tableInvoice &&
            o[DbConstants.columnOp] == DbConstants.opInsert,
      ),
      hasLength(1),
    );
    final lineOps = mine
        .where(
          (o) => o[DbConstants.columnTableName] == DbConstants.tableInvoiceLine,
        )
        .toList();
    expect(lineOps, hasLength(2));
    expect(
      lineOps.every((o) => o[DbConstants.columnOp] == DbConstants.opInsert),
      isTrue,
    );

    // All-or-none: invoice + lines + ops committed together.
    final stored = await invoices.getInvoices();
    expect(stored.map((i) => i.id), contains(invoice.id));
    expect(stored.firstWhere((i) => i.id == invoice.id).lines, hasLength(2));
  });

  test('update path enqueues update + line delete/insert ops', () async {
    final p1 = await products.insertProduct(model: 'U1', name: 'u1');
    await registerProducts([p1]);
    final created = await invoices.insert(
      customerName: 'Acme',
      currency: 'USD',
      date: DateTime(2026, 1, 2),
      total: 10,
      discount: 0,
      lines: [InvoiceTableRow(product: p1, amount: 1, unitPrice: 10)],
    );
    final before = (await outboxRows(db)).length;
    final lineIdBefore = (await db.query(
      DbConstants.tableInvoiceLine,
      columns: [DbConstants.columnId],
      where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
      whereArgs: [created.id],
    )).first[DbConstants.columnId];

    await invoices.insert(
      customerName: 'Acme',
      currency: 'USD',
      date: DateTime(2026, 1, 3),
      total: 20,
      discount: 0,
      invoiceId: created.id,
      lines: [InvoiceTableRow(product: p1, amount: 2, unitPrice: 10)],
    );

    final ops = (await outboxRows(db)).skip(before).toList();
    final invoiceOps = ops
        .where(
          (o) => o[DbConstants.columnTableName] == DbConstants.tableInvoice,
        )
        .toList();
    expect(invoiceOps, hasLength(1));
    expect(invoiceOps.first[DbConstants.columnOp], DbConstants.opUpdate);
    final lineOps = ops
        .where(
          (o) => o[DbConstants.columnTableName] == DbConstants.tableInvoiceLine,
        )
        .toList();
    // Same product survives: updated in place (stable _id), never
    // delete + reinsert (which would orphan the server twin).
    expect(lineOps, hasLength(1));
    expect(lineOps.first[DbConstants.columnOp], DbConstants.opUpdate);
    final lineIds = await db.query(
      DbConstants.tableInvoiceLine,
      columns: [DbConstants.columnId],
      where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
      whereArgs: [created.id],
    );
    expect(lineIds, hasLength(1));
    expect(lineIds.first[DbConstants.columnId], lineIdBefore);
  });

  test('delete soft-deletes invoice + lines and hides from reads', () async {
    final p1 = await products.insertProduct(model: 'D1', name: 'd1');
    await registerProducts([p1]);
    final created = await invoices.insert(
      customerName: 'Doomed',
      currency: 'USD',
      date: DateTime(2026, 1, 2),
      total: 10,
      discount: 0,
      lines: [InvoiceTableRow(product: p1, amount: 1, unitPrice: 10)],
    );
    final before = (await outboxRows(db)).length;

    await invoices.delete(created);

    final ops = (await outboxRows(db)).skip(before).toList();
    expect(
      ops.where(
        (o) =>
            o[DbConstants.columnTableName] == DbConstants.tableInvoice &&
            o[DbConstants.columnOp] == DbConstants.opDelete,
      ),
      hasLength(1),
    );
    expect(
      ops.where(
        (o) =>
            o[DbConstants.columnTableName] == DbConstants.tableInvoiceLine &&
            o[DbConstants.columnOp] == DbConstants.opDelete,
      ),
      hasLength(1),
    );

    expect(await invoices.getInvoices(), isEmpty);

    final rawInvoice = await db.query(
      DbConstants.tableInvoice,
      where: '_id = ?',
      whereArgs: [created.id],
    );
    expect(rawInvoice.first[DbConstants.columnIsDeleted], 1);
  });

  test('customer search skips soft-deleted invoices', () async {
    final p1 = await products.insertProduct(model: 'C1', name: 'c1');
    await registerProducts([p1]);
    final gone = await invoices.insert(
      customerName: 'Ghost Customer',
      currency: 'USD',
      date: DateTime(2026, 1, 2),
      total: 5,
      discount: 0,
      lines: [InvoiceTableRow(product: p1, amount: 1, unitPrice: 5)],
    );
    final kept = await invoices.insert(
      customerName: 'Ghost Town Traders',
      currency: 'USD',
      date: DateTime(2026, 1, 2),
      total: 5,
      discount: 0,
      lines: [InvoiceTableRow(product: p1, amount: 1, unitPrice: 5)],
    );
    expect(await customers.search('Ghost'), hasLength(2));

    await invoices.delete(gone);

    final names = await customers.search('Ghost');
    expect(names, isNot(contains('Ghost Customer')));
    expect(names, contains(kept.customerName));
  });
}
