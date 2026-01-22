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
          REFERENCES ${DbConstants.tablePriceCategory}(${DbConstants.columnId}) ON DELETE CASCADE,
        UNIQUE(${DbConstants.columnPricesProductId}, ${DbConstants.columnPricesPriceCategoryId}) 
          ON CONFLICT REPLACE
      )
    ''');

    // Sync tables
    await _createSyncTables(db);

    // Indexes for sync queries
    await _createSyncIndexes(db);

    // seed initial products
    await DbSeeder.seedProducts(db);
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

    await _backfillProductsUuids(db);

    final tables = [
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

  static Future<void> _backfillProductsUuids(Database db) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final products = await db.query(DbConstants.tableProduct);
    for (final row in products) {
      final id = row[DbConstants.columnId] as int;
      final model = row[DbConstants.columnProductModel] as String;

      // Check if this is a seeded product
      final seededProduct = DbSeeder.products.firstWhere(
        (p) => p['model'] == model,
        orElse: () => {},
      );

      final uuid = seededProduct.isNotEmpty
          ? seededProduct['uuid']
                as String // Use deterministic UUID
          : const Uuid().v4(); // Random for user-created

      await db.update(
        DbConstants.tableProduct,
        {'uuid': uuid, 'updated_at': now},
        where: '${DbConstants.columnId} = ?',
        whereArgs: [id],
      );
    }
  }
}

class DbSeeder {
  static const products = [
    {
      '_id': 1,
      DbConstants.columnUuid: 'seed-product-id-0001',
      DbConstants.columnProductModel: 'A1',
      DbConstants.columnProductName: 'مشد صدر',
    },
    {
      '_id': 2,
      DbConstants.columnUuid: 'seed-product-id-0002',
      DbConstants.columnProductModel: 'A1+',
      DbConstants.columnProductName: 'مشد صدر عريض',
    },
    {
      '_id': 3,
      DbConstants.columnUuid: 'seed-product-id-0003',
      DbConstants.columnProductModel: 'B1',
      DbConstants.columnProductName: 'مشد حزام بطن',
    },
    {
      '_id': 4,
      DbConstants.columnUuid: 'seed-product-id-0004',
      DbConstants.columnProductModel: 'D1',
      DbConstants.columnProductName: 'سليب بطن',
    },
    {
      '_id': 5,
      DbConstants.columnUuid: 'seed-product-id-0005',
      DbConstants.columnProductModel: 'D2',
      DbConstants.columnProductName: 'سليب بطن ظهر عالي',
    },
    {
      '_id': 6,
      DbConstants.columnUuid: 'seed-product-id-0006',
      DbConstants.columnProductModel: 'C1',
      DbConstants.columnProductName: 'شورت فوق الركبة',
    },
    {
      '_id': 8,
      DbConstants.columnUuid: 'seed-product-id-0008',
      DbConstants.columnProductModel: 'C2',
      DbConstants.columnProductName: 'شورت تحت الركبة',
    },
    {
      '_id': 9,
      DbConstants.columnUuid: 'seed-product-id-0009',
      DbConstants.columnProductModel: 'A2',
      DbConstants.columnProductName: 'مشد بودي صدر مع بطن',
    },
    {
      '_id': 10,
      DbConstants.columnUuid: 'seed-product-id-0010',
      DbConstants.columnProductModel: 'A3',
      DbConstants.columnProductName: 'مشد بودي مع أكمام',
    },
    {
      '_id': 11,
      DbConstants.columnUuid: 'seed-product-id-0011',
      DbConstants.columnProductModel: 'H1',
      DbConstants.columnProductName: 'مشد ذراعين',
    },
    {
      '_id': 12,
      DbConstants.columnUuid: 'seed-product-id-0012',
      DbConstants.columnProductModel: 'H2',
      DbConstants.columnProductName: 'مشد ذراعين عريض',
    },
    {
      '_id': 13,
      DbConstants.columnUuid: 'seed-product-id-0013',
      DbConstants.columnProductModel: 'K1',
      DbConstants.columnProductName: 'شورت فوق الركبة مع خلفية تول',
    },
    {
      '_id': 14,
      DbConstants.columnUuid: 'seed-product-id-0014',
      DbConstants.columnProductModel: 'K2',
      DbConstants.columnProductName: 'شورت تحت الركبة مع خلفية تول',
    },
    {
      '_id': 15,
      DbConstants.columnUuid: 'seed-product-id-0015',
      DbConstants.columnProductModel: 'K3',
      DbConstants.columnProductName: 'أفارول فوق الركبة مع خلفية تول',
    },
    {
      '_id': 16,
      DbConstants.columnUuid: 'seed-product-id-0016',
      DbConstants.columnProductModel: 'K4',
      DbConstants.columnProductName: 'أفارول للكاحل مع خلفية تول',
    },
    {
      '_id': 17,
      DbConstants.columnUuid: 'seed-product-id-0017',
      DbConstants.columnProductModel: 'K5',
      DbConstants.columnProductName: 'أفارول كامل مع يدين مع خلفية تول',
    },
    {
      '_id': 18,
      DbConstants.columnUuid: 'seed-product-id-0018',
      DbConstants.columnProductModel: 'E1',
      DbConstants.columnProductName: 'مشد تثدي رجالي',
    },
    {
      '_id': 19,
      DbConstants.columnUuid: 'seed-product-id-0019',
      DbConstants.columnProductModel: 'E2',
      DbConstants.columnProductName: 'كنزة حفر رجالي',
    },
    {
      '_id': 20,
      DbConstants.columnUuid: 'seed-product-id-0020',
      DbConstants.columnProductModel: 'E3',
      DbConstants.columnProductName: 'أفارول رجالي فوق الركبة',
    },
    {
      '_id': 21,
      DbConstants.columnUuid: 'seed-product-id-0021',
      DbConstants.columnProductModel: 'G1',
      DbConstants.columnProductName: 'أفارول نسائي فوق الركبة',
    },
    {
      '_id': 22,
      DbConstants.columnUuid: 'seed-product-id-0022',
      DbConstants.columnProductModel: 'G2',
      DbConstants.columnProductName: 'أفارول نسائي للكاحل',
    },
    {
      '_id': 23,
      DbConstants.columnUuid: 'seed-product-id-0023',
      DbConstants.columnProductModel: 'M1',
      DbConstants.columnProductName: 'مشد فخذين',
    },
    {
      '_id': 24,
      DbConstants.columnUuid: 'seed-product-id-0024',
      DbConstants.columnProductModel: 'C3',
      DbConstants.columnProductName: 'مشد طويل للكاحل',
    },
    {
      '_id': 25,
      DbConstants.columnUuid: 'seed-product-id-0025',
      DbConstants.columnProductModel: 'S1',
      DbConstants.columnProductName: 'مشد عنق',
    },
    {
      '_id': 26,
      DbConstants.columnUuid: 'seed-product-id-0026',
      DbConstants.columnProductModel: 'S2',
      DbConstants.columnProductName: 'مشد وجه',
    },
  ];

  static Future<void> seedProducts(Database db) async {
    final storedProductsCount = await db
        .rawQuery('''select count (*) from ${DbConstants.tableProduct}''')
        .then((value) => value.first.values.first as int);

    if (storedProductsCount == 0) {
      final batch = db.batch();
      for (final product in products) {
        batch.insert(DbConstants.tableProduct, product);
      }
      await batch.commit(noResult: true);
    }
  }
}
