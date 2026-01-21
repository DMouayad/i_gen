import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'db_constants.dart';

class DbProvider {
  static Future<Database> open() async {
    final dbDir = await getApplicationSupportDirectory();
    final dbPath = p.join(dbDir.path, 'i_gen.db');

    return openDatabase(
      dbPath,
      version: 2, // Bumped from 1
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
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
    await db.execute('''
      CREATE INDEX idx_customer_name 
      ON ${DbConstants.tableInvoice}(${DbConstants.columnCustomerName})
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
          REFERENCES ${DbConstants.tableProduct}(${DbConstants.columnId}) ON DELETE RESTRICT,
        UNIQUE(${DbConstants.columnInvoiceLineInvoiceId}, ${DbConstants.columnInvoiceLineProductId}) 
          ON CONFLICT REPLACE
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
          REFERENCES ${DbConstants.tableProduct}(${DbConstants.columnId}) ON DELETE CASCADE,
        FOREIGN KEY(${DbConstants.columnPricesPriceCategoryId}) 
          REFERENCES ${DbConstants.tablePriceCategory}(${DbConstants.columnId}),
        UNIQUE(${DbConstants.columnPricesProductId}, ${DbConstants.columnPricesPriceCategoryId}) 
          ON CONFLICT REPLACE
      )
    ''');

    // Sync tables
    await _createSyncTables(db);

    // Indexes for sync queries
    await _createSyncIndexes(db);
  }

  static Future<void> _createSyncTables(Database db) async {
    // Tombstones - tracks deleted records
    await db.execute('''
      CREATE TABLE ${DbConstants.tableSyncTombstones} (
        table_name TEXT NOT NULL,
        uuid TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        PRIMARY KEY (table_name, uuid)
      )
    ''');

    // Sync history - tracks last sync per device
    await db.execute('''
      CREATE TABLE ${DbConstants.tableSyncHistory} (
        device_id TEXT PRIMARY KEY,
        device_name TEXT,
        last_sync_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _createSyncIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX idx_product_updated ON ${DbConstants.tableProduct}(${DbConstants.columnUpdatedAt})',
    );
    await db.execute(
      'CREATE INDEX idx_invoice_updated ON ${DbConstants.tableInvoice}(${DbConstants.columnUpdatedAt})',
    );
    await db.execute(
      'CREATE INDEX idx_invoice_line_updated ON ${DbConstants.tableInvoiceLine}(${DbConstants.columnUpdatedAt})',
    );
    await db.execute(
      'CREATE INDEX idx_tombstone_deleted ON ${DbConstants.tableSyncTombstones}(deleted_at)',
    );
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _migrateToV2(db);
    }
  }

  static Future<void> _migrateToV2(Database db) async {
    final tables = [
      DbConstants.tableProduct,
      DbConstants.tableInvoice,
      DbConstants.tableInvoiceLine,
      DbConstants.tablePriceCategory,
      DbConstants.tablePrices,
    ];

    // Add sync columns to each table
    for (final table in tables) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN ${DbConstants.columnUuid} TEXT',
      );
      await db.execute(
        'ALTER TABLE $table ADD COLUMN ${DbConstants.columnUpdatedAt} INTEGER NOT NULL DEFAULT 0',
      );
    }

    // Create sync tables
    await _createSyncTables(db);
    await _createSyncIndexes(db);

    // Create unique indexes on uuid
    for (final table in tables) {
      await db.execute(
        'CREATE UNIQUE INDEX idx_${table}_uuid ON $table(${DbConstants.columnUuid})',
      );
    }

    // Backfill existing records with UUIDs
    await _backfillUuids(db);
  }

  static Future<void> _backfillUuids(Database db) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final uuid = const Uuid();

    final tables = [
      DbConstants.tableProduct,
      DbConstants.tableInvoice,
      DbConstants.tableInvoiceLine,
      DbConstants.tablePriceCategory,
      DbConstants.tablePrices,
    ];

    for (final table in tables) {
      final rows = await db.query(table, columns: [DbConstants.columnId]);
      for (final row in rows) {
        await db.update(
          table,
          {DbConstants.columnUuid: uuid.v4(), DbConstants.columnUpdatedAt: now},
          where: '${DbConstants.columnId} = ?',
          whereArgs: [row[DbConstants.columnId]],
        );
      }
    }
  }
}

class DbSeeder {
  static Future<void> seedProducts(Database db) async {
    final storedProductsCount = await db
        .rawQuery('''select count (*) from ${DbConstants.tableProduct}''')
        .then((value) => value.first.values.first as int);
    if (storedProductsCount == 0) {
      final products = [
        {'_id': 1, 'model': 'A1', 'name': 'مشد صدر'},
        {'_id': 2, 'model': 'A1+', 'name': 'مشد صدر عريض'},
        {'_id': 3, 'model': 'B1', 'name': 'مشد حزام بطن'},
        {'_id': 4, 'model': 'D1', 'name': 'سليب بطن'},
        {'_id': 5, 'model': 'D2', 'name': 'سليب بطن ظهر عالي'},
        {'_id': 6, 'model': 'C1', 'name': 'شورت فوق الركبة'},
        {'_id': 8, 'model': 'C2', 'name': 'شورت تحت الركبة'},
        {'_id': 9, 'model': 'A2', 'name': 'مشد بودي صدر مع بطن'},
        {'_id': 10, 'model': 'A3', 'name': 'مشد بودي مع أكمام'},
        {'_id': 11, 'model': 'H1', 'name': 'مشد ذراعين'},
        {'_id': 12, 'model': 'H2', 'name': 'مشد ذراعين عريض'},
        {'_id': 13, 'model': 'K1', 'name': 'شورت فوق الركبة مع خلفية تول'},
        {'_id': 14, 'model': 'K2', 'name': 'شورت تحت الركبة مع خلفية تول'},
        {'_id': 15, 'model': 'K3', 'name': 'أفارول فوق الركبة مع خلفية تول'},
        {'_id': 16, 'model': 'K4', 'name': 'أفارول للكاحل مع خلفية تول'},
        {'_id': 17, 'model': 'K5', 'name': 'أفارول كامل مع يدين مع خلفية تول'},
        {'_id': 18, 'model': 'E1', 'name': 'مشد تثدي رجالي'},
        {'_id': 19, 'model': 'E2', 'name': 'كنزة حفر رجالي'},
        {'_id': 20, 'model': 'E3', 'name': 'أفارول رجالي فوق الركبة'},
        {'_id': 21, 'model': 'G1', 'name': 'أفارول نسائي فوق الركبة'},
        {'_id': 22, 'model': 'G2', 'name': 'أفارول نسائي للكاحل'},
        {'_id': 23, 'model': 'M1', 'name': 'مشد فخذين'},
        {'_id': 24, 'model': 'C3', 'name': 'مشد طويل للكاحل'},
        {'_id': 25, 'model': 'S1', 'name': 'مشد عنق'},
        {'_id': 26, 'model': 'S2', 'name': 'مشد وجه'},
      ];

      final batch = db.batch();
      for (final product in products) {
        batch.insert(DbConstants.tableProduct, product);
      }
      await batch.commit(noResult: true);
    }
  }
}
