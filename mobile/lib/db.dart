import 'dart:math';

import 'package:sqflite/sqflite.dart';

/// One mutation to a synced row: the triple that travels together to the
/// outbox (replaces the old table/rowId/op parameter clump).
class MutationRef {
  const MutationRef({
    required this.table,
    required this.rowId,
    required this.op,
  });

  final String table;
  final int rowId;

  /// One of [DbConstants.opInsert], [DbConstants.opUpdate], [DbConstants.opDelete].
  final String op;
}

class DbConstants {
  static const String tableProduct = 'product';
  static const String columnId = '_id';
  static const String columnProductModel = 'model';
  static const String columnProductName = 'name';

  /// JSON array of size labels (e.g. `["S","M","L"]`), `[]` when sizeless.
  /// Sorted by `kSizeOrder` on write; unknown labels sort last.
  static const String columnProductSizes = 'sizes';

  //
  static const String tableInvoiceLine = 'invoice_line';
  static const String columnInvoiceLineInvoiceId = 'invoice_id';
  static const String columnInvoiceLineProductId = 'product_id';
  static const String columnInvoiceLineAmount = 'amount';
  static const String columnInvoiceLinePrice = 'price';

  /// Size label for a line (`''` = sizeless). NOT NULL with `''` default on
  /// purpose: NULLs are distinct in a UNIQUE index, so nullable sizes would
  /// let duplicate sizeless lines pile up instead of replacing. Models map
  /// `''` ↔ null at the boundary ([InvoiceLine.encodeSize]/[decodeSize]).
  static const String columnInvoiceLineSize = 'size';

  //
  static const String tableInvoice = 'invoice';
  static const String columnCustomerName = 'customer';
  static const String columnInvoiceDate = 'date';
  static const String columnInvoiceTotal = 'total';
  static const String columnInvoiceCurrency = 'currency';
  static const String columnInvoiceDiscount = 'discount';
  static const String columnInvoiceOrderId = 'order_id';

  //
  static const String tableInvoiceLines = 'invoice_lines';
  //
  static const String tablePrices = 'prices';
  static const String columnPricesProductId = 'product_id';
  static const String columnPricesPrice = 'price';
  static const String columnPricesPriceCategoryId = 'category_id';

  //
  static const String tablePriceCategory = 'price_category';
  static const String columnPriceCategoryId = '_id';
  static const String columnPriceCategoryName = 'name';
  static const String columnPriceCategoryCurrency = 'currency';

  // Phase 2 — per-row sync metadata (all five business tables).
  static const String columnRemoteId = 'remote_id';
  static const String columnUpdatedAt = 'updated_at';
  static const String columnIsDeleted = 'is_deleted';

  // Phase 2 — outbox queue of pending offline operations.
  static const String tableOutbox = 'outbox';
  static const String columnOpId = 'op_id';
  static const String columnTableName = 'table_name';
  static const String columnRowId = 'row_id';
  static const String columnOp = 'op';
  static const String columnPayload = 'payload';
  static const String columnCreatedAt = 'created_at';
  static const String columnAttempts = 'attempts';
  static const String columnLastError = 'last_error';

  static const String opInsert = 'insert';
  static const String opUpdate = 'update';
  static const String opDelete = 'delete';

  // Phase 2 — per-table pull checkpoints.
  static const String tableSyncState = 'sync_state';
  static const String columnLastPullAt = 'last_pull_at';

  /// The five business tables that participate in sync.
  static const List<String> syncedTables = [
    tableProduct,
    tableInvoice,
    tableInvoiceLine,
    tablePrices,
    tablePriceCategory,
  ];

  // Phase 3/5 — sync policy knobs (single source; engine and maintenance
  // both read these, so the parked threshold can never drift apart again).
  /// An op counts as parked (dead-letter) after this many failed attempts.
  static const int parkedAfterAttempts = 5;

  /// Parked ops are capped; oldest evicted first (with a visible warning).
  static const int maxParkedOps = 200;

  /// Soft-deleted rows older than this are purged on startup.
  static const Duration tombstoneRetention = Duration(days: 30);

  /// Payloads larger than this log a warning (visible, not silently slow).
  static const int payloadWarnBytes = 300 * 1024;

  /// Client-generated outbox idempotency key: unique per operation.
  static String newOpId() {
    final rand = Random.secure();
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = rand.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return '$micros-$suffix';
  }

  /// Deterministic idempotency key for catalog seed rows: every install
  /// computes the same key for the same natural key, so a second device's
  /// push upserts onto the first device's server row (same owner) instead
  /// of creating a duplicate twin that later breaks pull merges
  /// (UNIQUE(model) abort + orphan price skips).
  static String seedOpId(String table, String naturalKey) =>
      'seed-$table-$naturalKey';

  /// `updated_at` stamp for freshly seeded catalog rows. Epoch-old on
  /// purpose: any server truth (millis-since-epoch) is strictly newer, so a
  /// pull twin-merge overwrites pristine seed defaults instead of tying on
  /// `now` and keeping the stale content. Real edits bump via `withStamp`
  /// and the push ack writes the server timestamp back — only pristine,
  /// never-pushed seeds carry this value, so it also marks "safe for the
  /// server to win" in the twin merge.
  static const int seedUpdatedAt = 1;

  /// True for best-effort catalog-seed ops (see [seedOpId]). Seed pushes are
  /// convergence hints, not user data: when the server refuses them the
  /// device heals via pull, so they must never park as errors.
  /// Scoped to the product seed stream (the only seed writer today); the
  /// full `seed-product-` prefix keeps random op ids from ever matching.
  static bool isSeedOpId(String table, String opId) =>
      table == tableProduct && opId.startsWith('seed-$tableProduct-');
}

class DbProvider {
  static const int dbVersion = 5;

  /// Name of the live sqlite file. Single source of truth — `injectDependencies`
  /// (`mobile/lib/di.dart`) and the backup flow (`mobile/lib/utils/backup_flow.dart`) both
  /// build the absolute path from this.
  static const String dbFileName = 'i_gen.db';

  static Future<Database> open(String path) async {
    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: (Database db, int version) async {
        await createV1Tables(db);
        await applyV2Migration(db);
        await applyV3Migration(db);
        await applyV4Migration(db);
        await applyV5Migration(db);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await applyV2Migration(db);
        }
        if (oldVersion < 3) {
          await applyV3Migration(db);
        }
        if (oldVersion < 4) {
          await applyV4Migration(db);
        }
        if (oldVersion < 5) {
          await applyV5Migration(db);
        }
      },
    );
  }

  /// Original version-1 schema. Kept intact so upgrades and fresh installs
  /// share one definition.
  static Future<void> createV1Tables(Database db) async {
    await db.execute('''
create table ${DbConstants.tableProduct} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnProductModel} text not null unique,
  ${DbConstants.columnProductName} text not null)
''');
    await db.execute('''
create table ${DbConstants.tableInvoice} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnInvoiceTotal} REAL not null,
  ${DbConstants.columnCustomerName} text not null,
  ${DbConstants.columnInvoiceDate} text not null,
  ${DbConstants.columnInvoiceCurrency} text not null,
  ${DbConstants.columnInvoiceDiscount} REAL not null
  )
''');
    await db.execute('''
create INDEX "customer_name" on ${DbConstants.tableInvoice} ( ${DbConstants.columnCustomerName} )
 ''');
    // Known exception to the "no REPLACE on synced tables" invariant:
    // these two child tables use `UNIQUE ... ON CONFLICT REPLACE` as a
    // local upsert. Repos write update-in-place so REPLACE rarely fires,
    // and removing it needs a v3 migration (new failure mode: UNIQUE
    // throws instead of upserting). Left as-is deliberately — do not
    // add REPLACE to any other synced table.
    await db.execute('''
create table ${DbConstants.tableInvoiceLine} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnInvoiceLineInvoiceId} integer not null,
  ${DbConstants.columnInvoiceLineProductId} integer not null,
  ${DbConstants.columnInvoiceLineAmount} integer not null,
  ${DbConstants.columnInvoiceLinePrice} REAL not null,
  foreign key(${DbConstants.columnInvoiceLineInvoiceId}) references ${DbConstants.tableInvoice}(${DbConstants.columnId}),
  foreign key(${DbConstants.columnInvoiceLineProductId}) references ${DbConstants.tableProduct}(${DbConstants.columnId}) ON DELETE RESTRICT
  unique(${DbConstants.columnInvoiceLineInvoiceId}, ${DbConstants.columnInvoiceLineProductId}) ON CONFLICT REPLACE

  )
''');

    await db.execute('''
create table ${DbConstants.tablePrices} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnPricesProductId} integer not null,
  ${DbConstants.columnPricesPrice} REAL not null,
  ${DbConstants.columnPricesPriceCategoryId} integer not null,
  foreign key(${DbConstants.columnPricesProductId}) references ${DbConstants.tableProduct}(${DbConstants.columnId}) ON DELETE CASCADE,
  foreign key(${DbConstants.columnPricesPriceCategoryId}) references ${DbConstants.tablePriceCategory}(${DbConstants.columnId})
  unique(${DbConstants.columnPricesProductId}, ${DbConstants.columnPricesPriceCategoryId}) ON CONFLICT REPLACE
  )
''');
    await db.execute('''
create table ${DbConstants.tablePriceCategory} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnPriceCategoryName} text not null unique,
  ${DbConstants.columnPriceCategoryCurrency} text not null
  )
''');
  }

  /// Version 2 migration (Phase 2 spec). Additive only: three columns per
  /// business table plus the `outbox` and `sync_state` bookkeeping tables.
  /// Existing rows get `updated_at` backfilled with the migration time;
  /// `remote_id` stays null so the first sync pushes them as inserts.
  ///
  /// Note: the spec writes the column as `remote_id TEXT UNIQUE`, but SQLite
  /// rejects UNIQUE inside `ADD COLUMN` ("Cannot add a UNIQUE column"), so
  /// the column is added plain and uniqueness is enforced with an equivalent
  /// `CREATE UNIQUE INDEX` (multiple NULLs allowed in both variants).
  static Future<void> applyV2Migration(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final table in DbConstants.syncedTables) {
      await db.execute(
        'ALTER TABLE $table '
        'ADD COLUMN ${DbConstants.columnRemoteId} TEXT',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_${table}_remote_id '
        'ON $table (${DbConstants.columnRemoteId})',
      );
      await db.execute(
        'ALTER TABLE $table '
        'ADD COLUMN ${DbConstants.columnUpdatedAt} INTEGER',
      );
      await db.execute(
        'ALTER TABLE $table '
        'ADD COLUMN ${DbConstants.columnIsDeleted} INTEGER NOT NULL DEFAULT 0',
      );
      await db.update(table, {
        DbConstants.columnUpdatedAt: now,
      }, where: '${DbConstants.columnUpdatedAt} IS NULL');
    }
    await db.execute('''
create table if not exists ${DbConstants.tableOutbox} (
  ${DbConstants.columnOpId} TEXT primary key,
  ${DbConstants.columnTableName} TEXT not null,
  ${DbConstants.columnRowId} integer not null,
  ${DbConstants.columnOp} TEXT not null,
  ${DbConstants.columnPayload} TEXT not null,
  ${DbConstants.columnCreatedAt} integer not null,
  ${DbConstants.columnAttempts} integer not null default 0,
  ${DbConstants.columnLastError} TEXT
  )
''');
    await db.execute('''
create index if not exists idx_outbox_fifo
  on ${DbConstants.tableOutbox} (${DbConstants.columnTableName}, ${DbConstants.columnCreatedAt})
''');
    await db.execute('''
create table if not exists ${DbConstants.tableSyncState} (
  ${DbConstants.columnTableName} TEXT primary key,
  ${DbConstants.columnLastPullAt} integer
  )
''');
  }

  /// Version 3 migration: product sizes. Additive only — one JSON column;
  /// existing rows (and fresh seeds) are sizeless (`[]`). The sync engine
  /// maps the column by name in both directions, so no engine change is
  /// needed; the server needs `alter table products add column sizes text`.
  static Future<void> applyV3Migration(Database db) async {
    await db.execute(
      'ALTER TABLE ${DbConstants.tableProduct} '
      "ADD COLUMN ${DbConstants.columnProductSizes} TEXT NOT NULL DEFAULT '[]'",
    );
    await db.update(DbConstants.tableProduct, {
      DbConstants.columnProductSizes: '[]',
    }, where: '${DbConstants.columnProductSizes} IS NULL');
  }

  /// Version 4 migration: per-line sizes. The UNIQUE key widens from
  /// `(invoice_id, product_id)` to `(invoice_id, product_id, size)` — SQLite
  /// cannot alter constraints, so the table is rebuilt: `_id`s are carried
  /// over explicitly (outbox `row_id`s and `remote_id` matches survive) and
  /// every existing line becomes sizeless (`''`). The sync engine maps the
  /// column by name in both directions; the server needs
  /// `alter table invoice_lines add column size text not null default ''`.
  static Future<void> applyV4Migration(Database db) async {
    await db.execute('''
create table ${DbConstants.tableInvoiceLine}_new (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnInvoiceLineInvoiceId} integer not null,
  ${DbConstants.columnInvoiceLineProductId} integer not null,
  ${DbConstants.columnInvoiceLineAmount} integer not null,
  ${DbConstants.columnInvoiceLinePrice} REAL not null,
  ${DbConstants.columnInvoiceLineSize} TEXT NOT NULL DEFAULT '',
  ${DbConstants.columnRemoteId} TEXT,
  ${DbConstants.columnUpdatedAt} INTEGER,
  ${DbConstants.columnIsDeleted} INTEGER NOT NULL DEFAULT 0,
  foreign key(${DbConstants.columnInvoiceLineInvoiceId}) references ${DbConstants.tableInvoice}(${DbConstants.columnId}),
  foreign key(${DbConstants.columnInvoiceLineProductId}) references ${DbConstants.tableProduct}(${DbConstants.columnId}) ON DELETE RESTRICT
  unique(${DbConstants.columnInvoiceLineInvoiceId}, ${DbConstants.columnInvoiceLineProductId}, ${DbConstants.columnInvoiceLineSize}) ON CONFLICT REPLACE
  )
''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_${DbConstants.tableInvoiceLine}_remote_id '
      'ON ${DbConstants.tableInvoiceLine}_new (${DbConstants.columnRemoteId})',
    );
    await db.execute('''
INSERT INTO ${DbConstants.tableInvoiceLine}_new (
  ${DbConstants.columnId},
  ${DbConstants.columnInvoiceLineInvoiceId},
  ${DbConstants.columnInvoiceLineProductId},
  ${DbConstants.columnInvoiceLineAmount},
  ${DbConstants.columnInvoiceLinePrice},
  ${DbConstants.columnRemoteId},
  ${DbConstants.columnUpdatedAt},
  ${DbConstants.columnIsDeleted},
  ${DbConstants.columnInvoiceLineSize}
) SELECT
  ${DbConstants.columnId},
  ${DbConstants.columnInvoiceLineInvoiceId},
  ${DbConstants.columnInvoiceLineProductId},
  ${DbConstants.columnInvoiceLineAmount},
  ${DbConstants.columnInvoiceLinePrice},
  ${DbConstants.columnRemoteId},
  ${DbConstants.columnUpdatedAt},
  ${DbConstants.columnIsDeleted},
  ''
FROM ${DbConstants.tableInvoiceLine}
''');
    await db.execute('DROP TABLE ${DbConstants.tableInvoiceLine}');
    await db.execute(
      'ALTER TABLE ${DbConstants.tableInvoiceLine}_new '
      'RENAME TO ${DbConstants.tableInvoiceLine}',
    );
  }

  /// Version 5 migration: invoice origin. Additive only — one nullable
  /// column; existing invoices simply have no order (`NULL`). The sync
  /// engine maps the column by name in both directions (unknown keys are
  /// skipped on old devices), and the server needs the matching nullable
  /// `order_id uuid REFERENCES orders(id)` — run that SQL before releasing
  /// any app version that writes the column.
  static Future<void> applyV5Migration(Database db) async {
    await db.execute(
      'ALTER TABLE ${DbConstants.tableInvoice} '
      'ADD COLUMN ${DbConstants.columnInvoiceOrderId} TEXT',
    );
  }
}

// DbSeeder moved to lib/db_seeder.dart (schema file stays dependency-free).
