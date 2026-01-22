// test/helpers/test_database.dart

import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import 'package:i_gen/db/db_constants.dart';

/// Initialize FFI for desktop testing
void initTestDatabase() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Counter to ensure unique database paths
int _dbCounter = 0;

/// Create a unique test database for each call
Future<Database> createTestDatabase() async {
  _dbCounter++;
  final timestamp = DateTime.now().microsecondsSinceEpoch;

  // Option 1: Use temp file (most reliable)
  final tempDir = Directory.systemTemp;
  final dbPath = path.join(tempDir.path, 'test_db_${_dbCounter}_$timestamp.db');

  // Delete if exists
  try {
    await databaseFactory.deleteDatabase(dbPath);
  } catch (_) {}

  final db = await databaseFactory.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: _createTables,
      singleInstance: false,
    ),
  );

  return db;
}

Future<void> _createTables(Database db, int version) async {
  // Product
  await db.execute('''
    CREATE TABLE ${DbConstants.tableProduct} (
      ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${DbConstants.columnProductModel} TEXT NOT NULL UNIQUE,
      ${DbConstants.columnProductName} TEXT NOT NULL,
      ${DbConstants.columnUuid} TEXT UNIQUE,
      ${DbConstants.columnUpdatedAt} INTEGER NOT NULL DEFAULT 0
    )
  ''');

  // Invoice
  await db.execute('''
    CREATE TABLE ${DbConstants.tableInvoice} (
      ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${DbConstants.columnInvoiceTotal} REAL NOT NULL,
      ${DbConstants.columnCustomerName} TEXT NOT NULL,
      ${DbConstants.columnInvoiceDate} TEXT NOT NULL,
      ${DbConstants.columnInvoiceCurrency} TEXT NOT NULL,
      ${DbConstants.columnInvoiceDiscount} REAL NOT NULL,
      ${DbConstants.columnUuid} TEXT UNIQUE,
      ${DbConstants.columnUpdatedAt} INTEGER NOT NULL DEFAULT 0
    )
  ''');

  // Invoice Line
  await db.execute('''
    CREATE TABLE ${DbConstants.tableInvoiceLine} (
      ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${DbConstants.columnInvoiceLineInvoiceId} INTEGER NOT NULL,
      ${DbConstants.columnInvoiceLineProductId} INTEGER NOT NULL,
      ${DbConstants.columnInvoiceLineAmount} INTEGER NOT NULL,
      ${DbConstants.columnInvoiceLinePrice} REAL NOT NULL,
      ${DbConstants.columnUuid} TEXT UNIQUE,
      ${DbConstants.columnUpdatedAt} INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(${DbConstants.columnInvoiceLineInvoiceId}) 
        REFERENCES ${DbConstants.tableInvoice}(${DbConstants.columnId}),
      FOREIGN KEY(${DbConstants.columnInvoiceLineProductId}) 
        REFERENCES ${DbConstants.tableProduct}(${DbConstants.columnId})
    )
  ''');

  // Price Category
  await db.execute('''
    CREATE TABLE ${DbConstants.tablePriceCategory} (
      ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${DbConstants.columnPriceCategoryName} TEXT NOT NULL UNIQUE,
      ${DbConstants.columnPriceCategoryCurrency} TEXT NOT NULL,
      ${DbConstants.columnUuid} TEXT UNIQUE,
      ${DbConstants.columnUpdatedAt} INTEGER NOT NULL DEFAULT 0
    )
  ''');

  // Prices
  await db.execute('''
    CREATE TABLE ${DbConstants.tablePrices} (
      ${DbConstants.columnId} INTEGER PRIMARY KEY AUTOINCREMENT,
      ${DbConstants.columnPricesProductId} INTEGER NOT NULL,
      ${DbConstants.columnPricesPrice} REAL NOT NULL,
      ${DbConstants.columnPricesPriceCategoryId} INTEGER NOT NULL,
      ${DbConstants.columnUuid} TEXT UNIQUE,
      ${DbConstants.columnUpdatedAt} INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(${DbConstants.columnPricesProductId}) 
        REFERENCES ${DbConstants.tableProduct}(${DbConstants.columnId}),
      FOREIGN KEY(${DbConstants.columnPricesPriceCategoryId}) 
        REFERENCES ${DbConstants.tablePriceCategory}(${DbConstants.columnId}),
      UNIQUE(${DbConstants.columnPricesProductId}, ${DbConstants.columnPricesPriceCategoryId})
    )
  ''');

  // Sync Tombstones
  await db.execute('''
    CREATE TABLE ${DbConstants.tableSyncTombstones} (
      table_name TEXT NOT NULL,
      uuid TEXT NOT NULL,
      deleted_at INTEGER NOT NULL,
      PRIMARY KEY (table_name, uuid)
    )
  ''');

  // Sync History
  await db.execute('''
    CREATE TABLE ${DbConstants.tableSyncHistory} (
      device_id TEXT PRIMARY KEY,
      device_name TEXT,
      last_sync_at INTEGER NOT NULL DEFAULT 0
    )
  ''');
}

/// Clean up test database after test
Future<void> deleteTestDatabase(Database db) async {
  final dbPath = db.path;
  await db.close();

  if (dbPath != inMemoryDatabasePath) {
    try {
      await databaseFactory.deleteDatabase(dbPath);
    } catch (_) {}
  }
}

/// Seed test data (unchanged)
Future<void> seedTestData(Database db) async {
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;

  await db.insert(DbConstants.tableProduct, {
    DbConstants.columnProductModel: 'PROD-001',
    DbConstants.columnProductName: 'Test Product 1',
    DbConstants.columnUuid: 'product-uuid-001',
    DbConstants.columnUpdatedAt: now,
  });

  await db.insert(DbConstants.tableProduct, {
    DbConstants.columnProductModel: 'PROD-002',
    DbConstants.columnProductName: 'Test Product 2',
    DbConstants.columnUuid: 'product-uuid-002',
    DbConstants.columnUpdatedAt: now,
  });

  await db.insert(DbConstants.tablePriceCategory, {
    DbConstants.columnPriceCategoryName: 'Retail',
    DbConstants.columnPriceCategoryCurrency: 'USD',
    DbConstants.columnUuid: 'category-uuid-001',
    DbConstants.columnUpdatedAt: now,
  });

  await db.insert(DbConstants.tablePrices, {
    DbConstants.columnPricesProductId: 1,
    DbConstants.columnPricesPriceCategoryId: 1,
    DbConstants.columnPricesPrice: 99.99,
    DbConstants.columnUuid: 'price-uuid-001',
    DbConstants.columnUpdatedAt: now,
  });

  await db.insert(DbConstants.tableInvoice, {
    DbConstants.columnCustomerName: 'Test Customer',
    DbConstants.columnInvoiceDate: DateTime.now().toIso8601String(),
    DbConstants.columnInvoiceTotal: 199.98,
    DbConstants.columnInvoiceCurrency: 'USD',
    DbConstants.columnInvoiceDiscount: 0,
    DbConstants.columnUuid: 'invoice-uuid-001',
    DbConstants.columnUpdatedAt: now,
  });

  await db.insert(DbConstants.tableInvoiceLine, {
    DbConstants.columnInvoiceLineInvoiceId: 1,
    DbConstants.columnInvoiceLineProductId: 1,
    DbConstants.columnInvoiceLineAmount: 2,
    DbConstants.columnInvoiceLinePrice: 99.99,
    DbConstants.columnUuid: 'line-uuid-001',
    DbConstants.columnUpdatedAt: now,
  });
}
