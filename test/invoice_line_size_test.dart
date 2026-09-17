import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helper.dart';

/// Sized invoice lines end-to-end: persist, re-read, re-save matching.
void main() {
  late Database db;
  late InvoiceRepo invoices;
  late ProductRepo products;

  setUp(() async {
    db = await openFreshTestDb();
    invoices = InvoiceRepo(db);
    products = ProductRepo(db);
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

  test('sized lines persist and re-read with sizes intact', () async {
    final p = await products.insertProduct(
      model: 'SZ',
      name: 'sized',
      sizes: ['S', 'M'],
    );
    await registerProducts([p]);

    final created = await invoices.insert(
      customerName: 'Acme',
      currency: 'USD',
      date: DateTime(2026, 1, 2),
      total: 30,
      discount: 0,
      lines: [
        InvoiceTableRow(product: p, amount: 1, unitPrice: 10, size: 'S'),
        InvoiceTableRow(product: p, amount: 2, unitPrice: 10, size: 'M'),
      ],
    );

    final stored = await invoices.getInvoices();
    final lines = stored.firstWhere((i) => i.id == created.id).lines;
    expect(lines, hasLength(2));
    expect({for (final l in lines) l.size: l.amount}, {'S': 1, 'M': 2});

    // Outbox payloads carry the size (sync maps it by column name).
    final ops = await outboxRows(db);
    final linePayloads = [
      for (final o in ops)
        if (o[DbConstants.columnTableName] == DbConstants.tableInvoiceLine)
          jsonDecode(o[DbConstants.columnPayload] as String)
              as Map<String, dynamic>,
    ];
    expect(linePayloads, hasLength(2));
    expect({for (final p in linePayloads) p['size'] as String}, {'S', 'M'});
  });

  test('re-save matches by (product, size): stable ids, no dupes', () async {
    final p = await products.insertProduct(
      model: 'SZ',
      name: 'sized',
      sizes: ['S', 'M'],
    );
    await registerProducts([p]);
    final created = await invoices.insert(
      customerName: 'Acme',
      currency: 'USD',
      date: DateTime(2026, 1, 2),
      total: 30,
      discount: 0,
      lines: [
        InvoiceTableRow(product: p, amount: 1, unitPrice: 10, size: 'S'),
        InvoiceTableRow(product: p, amount: 2, unitPrice: 10, size: 'M'),
      ],
    );
    final idsBefore = <String, int>{
      for (final r in await db.query(
        DbConstants.tableInvoiceLine,
        columns: [DbConstants.columnId, DbConstants.columnInvoiceLineSize],
        where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
        whereArgs: [created.id],
      ))
        r[DbConstants.columnInvoiceLineSize] as String:
            r[DbConstants.columnId] as int,
    };

    // Drop S, change M's qty: S soft-deletes, M updates in place.
    await invoices.insert(
      customerName: 'Acme',
      currency: 'USD',
      date: DateTime(2026, 1, 3),
      total: 30,
      discount: 0,
      invoiceId: created.id,
      lines: [InvoiceTableRow(product: p, amount: 3, unitPrice: 10, size: 'M')],
    );

    final live = await db.query(
      DbConstants.tableInvoiceLine,
      where:
          '${DbConstants.columnInvoiceLineInvoiceId} = ? '
          'AND ${DbConstants.columnIsDeleted} = 0',
      whereArgs: [created.id],
    );
    expect(live, hasLength(1));
    expect(live.first[DbConstants.columnInvoiceLineSize], 'M');
    expect(live.first[DbConstants.columnId], idsBefore['M']);
    expect(live.first[DbConstants.columnInvoiceLineAmount], 3);

    final stored = await invoices.getInvoices();
    final lines = stored.firstWhere((i) => i.id == created.id).lines;
    expect(lines, hasLength(1));
    expect(lines.single.size, 'M');
    expect(lines.single.amount, 3);
  });
}
