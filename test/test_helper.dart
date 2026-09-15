import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:i_gen/db.dart';

/// Shared temp-database fixtures for sync tests (Phase 2 seam).
///
/// `flutter test` runs on the host VM where the sqflite method channel is
/// unavailable, so every helper routes through `sqflite_common_ffi`
/// (already a dependency — no pubspec change).
Future<void> initTestDatabaseFactory() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

Future<String> _tempDbPath() async {
  final dir = await Directory.systemTemp.createTemp('i_gen_sync_test');
  return p.join(dir.path, 'test.db');
}

/// Opens a fresh (v2) database at a temp path via the real [DbProvider].
Future<Database> openFreshTestDb() async {
  await initTestDatabaseFactory();
  return DbProvider.open(await _tempDbPath());
}

/// Builds a version-1 database fixture: the pre-migration schema with seed
/// rows. The v1 base is created by [DbProvider.createV1Tables] (the same
/// code the upgrade path builds on) so the fixture can never drift from the
/// real v1 schema; it must NOT gain sync columns, otherwise the upgrade
/// test is vacuous.
Future<Database> openV1Fixture() async {
  await initTestDatabaseFactory();
  final path = await _tempDbPath();
  final db = await openDatabase(
    path,
    version: 1,
    onCreate: (Database db, int version) async {
      await DbProvider.createV1Tables(db);
    },
  );

  final productA = await db.insert(DbConstants.tableProduct, {
    DbConstants.columnProductModel: 'T1',
    DbConstants.columnProductName: 't-one',
  });
  final productB = await db.insert(DbConstants.tableProduct, {
    DbConstants.columnProductModel: 'T2',
    DbConstants.columnProductName: 't-two',
  });
  final category = await db.insert(DbConstants.tablePriceCategory, {
    DbConstants.columnPriceCategoryName: 'retail',
    DbConstants.columnPriceCategoryCurrency: 'USD',
  });
  await db.insert(DbConstants.tablePrices, {
    DbConstants.columnPricesProductId: productA,
    DbConstants.columnPricesPrice: 9.5,
    DbConstants.columnPricesPriceCategoryId: category,
  });
  final invoice = await db.insert(DbConstants.tableInvoice, {
    DbConstants.columnInvoiceTotal: 19.0,
    DbConstants.columnCustomerName: 'acme',
    DbConstants.columnInvoiceDate: '2026-01-01',
    DbConstants.columnInvoiceCurrency: 'USD',
    DbConstants.columnInvoiceDiscount: 0.0,
  });
  await db.insert(DbConstants.tableInvoiceLine, {
    DbConstants.columnInvoiceLineInvoiceId: invoice,
    DbConstants.columnInvoiceLineProductId: productB,
    DbConstants.columnInvoiceLineAmount: 2,
    DbConstants.columnInvoiceLinePrice: 9.5,
  });
  return db;
}

/// Reopens [path] through the real [DbProvider] (runs pending migrations).
Future<Database> reopenViaProvider(String path) => DbProvider.open(path);

/// Row count helper.
Future<int> tableCount(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
  return (rows.first['c'] as int?) ?? 0;
}

/// Outbox rows oldest-first (FIFO order).
Future<List<Map<String, Object?>>> outboxRows(Database db) {
  return db.query(
    DbConstants.tableOutbox,
    orderBy: '${DbConstants.columnCreatedAt} ASC',
  );
}
