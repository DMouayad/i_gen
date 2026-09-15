import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/repos/sync_maintenance.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helper.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await openFreshTestDb();
    SyncTrigger.instance.counters.resetForTests();
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedProduct(
    String model, {
    required int updatedAt,
    int deleted = 0,
  }) {
    return db.insert(DbConstants.tableProduct, {
      DbConstants.columnProductModel: model,
      DbConstants.columnProductName: model,
      DbConstants.columnUpdatedAt: updatedAt,
      DbConstants.columnIsDeleted: deleted,
    });
  }

  Future<void> seedParkedOp(String table, int rowId, int createdAt) async {
    await db.insert(DbConstants.tableOutbox, {
      DbConstants.columnOpId: DbConstants.newOpId(),
      DbConstants.columnTableName: table,
      DbConstants.columnRowId: rowId,
      DbConstants.columnOp: DbConstants.opUpdate,
      DbConstants.columnPayload: '{"_id":$rowId}',
      DbConstants.columnCreatedAt: createdAt,
      DbConstants.columnAttempts: DbConstants.parkedAfterAttempts,
      DbConstants.columnLastError: 'boom',
    });
  }

  test('tombstone purge keeps 29-day rows and drops 31-day rows', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    const day = Duration.millisecondsPerDay;
    final keepId = await seedProduct(
      'KEEP',
      updatedAt: now - 29 * day,
      deleted: 1,
    );
    final dropId = await seedProduct(
      'DROP',
      updatedAt: now - 31 * day,
      deleted: 1,
    );
    final liveId = await seedProduct('LIVE', updatedAt: now - 60 * day);

    final removed = await SyncMaintenance.purgeTombstones(db);

    expect(removed, 1);
    expect(
      await db.query(
        DbConstants.tableProduct,
        where: '_id = ?',
        whereArgs: [dropId],
      ),
      isEmpty,
    );
    expect(
      (await db.query(
        DbConstants.tableProduct,
        where: '_id = ?',
        whereArgs: [keepId],
      )),
      hasLength(1),
    );
    expect(
      (await db.query(
        DbConstants.tableProduct,
        where: '_id = ?',
        whereArgs: [liveId],
      )),
      hasLength(1),
    );
  });

  test('parked cap evicts oldest-first and warns', () async {
    final base = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < DbConstants.maxParkedOps + 5; i++) {
      await seedParkedOp(DbConstants.tableProduct, i, base + i);
    }

    final evicted = await SyncMaintenance.enforceParkedCap(db);

    expect(evicted, 5);
    expect(SyncTrigger.instance.counters.parkedEvictions, 5);
    final remaining = await db.query(
      DbConstants.tableOutbox,
      orderBy: '${DbConstants.columnCreatedAt} ASC',
    );
    expect(remaining, hasLength(DbConstants.maxParkedOps));
    // Oldest (lowest created_at) are gone; newest survive.
    expect(remaining.first[DbConstants.columnRowId], 5);
    expect(
      remaining.last[DbConstants.columnRowId],
      DbConstants.maxParkedOps + 4,
    );
  });

  test('startup pass never throws on a v1-shaped database', () async {
    sqfliteFfiInit();
    final v1 = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE lonely (_id INTEGER PRIMARY KEY, v TEXT)',
          );
        },
      ),
    );
    try {
      final summary = await SyncMaintenance.runStartupMaintenance(v1);
      expect(summary.tombstonesPurged, 0);
      expect(summary.parkedEvicted, 0);
      final stats = await SyncMaintenance.readStats(v1);
      expect(stats.pendingTotal, 0);
      expect(stats.firstParkedError, isNull);
    } finally {
      await v1.close();
    }
  });

  test('readStats surfaces pending, parked error, and last sync', () async {
    await seedProduct('S1', updatedAt: SyncMetadata.nowMillis());
    await db.insert(DbConstants.tableOutbox, {
      DbConstants.columnOpId: DbConstants.newOpId(),
      DbConstants.columnTableName: DbConstants.tableProduct,
      DbConstants.columnRowId: 1,
      DbConstants.columnOp: DbConstants.opInsert,
      DbConstants.columnPayload: '{}',
      DbConstants.columnCreatedAt: SyncMetadata.nowMillis(),
      DbConstants.columnAttempts: 0,
      DbConstants.columnLastError: null,
    });
    await db.insert(DbConstants.tableOutbox, {
      DbConstants.columnOpId: DbConstants.newOpId(),
      DbConstants.columnTableName: DbConstants.tableInvoice,
      DbConstants.columnRowId: 7,
      DbConstants.columnOp: DbConstants.opUpdate,
      DbConstants.columnPayload: '{}',
      DbConstants.columnCreatedAt: SyncMetadata.nowMillis(),
      DbConstants.columnAttempts: 99,
      DbConstants.columnLastError: 'server exploded',
    });
    final pullAt = SyncMetadata.nowMillis();
    await db.insert(DbConstants.tableSyncState, {
      DbConstants.columnTableName: DbConstants.tableProduct,
      DbConstants.columnLastPullAt: pullAt,
    });

    final stats = await SyncMaintenance.readStats(db);

    expect(stats.pendingTotal, 2);
    expect(stats.parkedTotal, 1);
    expect(stats.pendingByTable[DbConstants.tableProduct], 1);
    expect(stats.pendingByTable[DbConstants.tableInvoice], 1);
    expect(stats.firstParkedError, contains('server exploded'));
    expect(stats.lastSyncAt?.millisecondsSinceEpoch, pullAt);
  });
}
