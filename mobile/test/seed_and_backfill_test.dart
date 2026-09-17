import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/db_seeder.dart';
import 'package:i_gen/repos/sync_maintenance.dart';
import 'package:sqflite/sqflite.dart';

import 'test_helper.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await openFreshTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'seedProducts enqueues 25 product outbox ops on fresh DB (Phase B)',
    () async {
      expect(await tableCount(db, DbConstants.tableProduct), 0);
      expect(await tableCount(db, DbConstants.tableOutbox), 0);

      await DbSeeder.seedProducts(db);

      expect(await tableCount(db, DbConstants.tableProduct), 25);
      final ops = await outboxRows(db);
      expect(ops, hasLength(25));
      for (final op in ops) {
        expect(op[DbConstants.columnTableName], DbConstants.tableProduct);
        expect(op[DbConstants.columnOp], DbConstants.opInsert);
        expect(op[DbConstants.columnAttempts], 0);
        expect(op[DbConstants.columnLastError], isNull);
        // Payload carries business columns, not just the `_id` fallback.
        expect(op[DbConstants.columnPayload], contains('model'));
      }
      // spot-check known models exist
      final a1 = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnProductModel} = ?',
        whereArgs: ['A1'],
      );
      expect(a1, hasLength(1));
      expect(a1.first[DbConstants.columnRemoteId], isNull);
      // Fresh seeds are epoch-old: any server row is strictly newer, so a
      // second device's pull overwrites pristine defaults (first-write-wins).
      final all = await db.query(DbConstants.tableProduct);
      expect(all, hasLength(25));
      for (final row in all) {
        expect(row[DbConstants.columnUpdatedAt], DbConstants.seedUpdatedAt);
      }
    },
  );

  test('seedProducts is idempotent — second call adds nothing', () async {
    await DbSeeder.seedProducts(db);
    final firstOps = await outboxRows(db);
    expect(firstOps, hasLength(25));

    await DbSeeder.seedProducts(db);

    expect(await tableCount(db, DbConstants.tableProduct), 25);
    expect(await outboxRows(db), hasLength(25));
  });

  test(
    'backfillSeedOutbox creates ops for existing install with empty outbox',
    () async {
      // Simulate old install: insert directly without outbox
      final id = await db.insert(DbConstants.tableProduct, {
        DbConstants.columnId: 99,
        DbConstants.columnProductModel: 'LEGACY',
        DbConstants.columnProductName: 'legacy',
        DbConstants.columnUpdatedAt: 1000,
        DbConstants.columnIsDeleted: 0,
        DbConstants.columnRemoteId: null,
      });
      expect(await tableCount(db, DbConstants.tableOutbox), 0);

      final backfilled = await SyncMaintenance.backfillSeedOutbox(db);
      expect(backfilled, 1);
      final ops = await outboxRows(db);
      expect(ops, hasLength(1));
      expect(ops.first[DbConstants.columnRowId], id);
      expect(ops.first[DbConstants.columnOp], DbConstants.opInsert);

      // idempotent second run
      final second = await SyncMaintenance.backfillSeedOutbox(db);
      expect(second, 0);
      expect(await outboxRows(db), hasLength(1));
    },
  );

  test('backfill ignores already-synced and deleted rows', () async {
    // synced row (remote_id set) should be ignored
    await db.insert(DbConstants.tableProduct, {
      DbConstants.columnProductModel: 'SYNCED',
      DbConstants.columnProductName: 'synced',
      DbConstants.columnUpdatedAt: 1000,
      DbConstants.columnIsDeleted: 0,
      DbConstants.columnRemoteId: 'remote-uuid',
    });
    // deleted row should be ignored
    await db.insert(DbConstants.tableProduct, {
      DbConstants.columnProductModel: 'DELETED',
      DbConstants.columnProductName: 'deleted',
      DbConstants.columnUpdatedAt: 1000,
      DbConstants.columnIsDeleted: 1,
      DbConstants.columnRemoteId: null,
    });
    // one eligible row
    await db.insert(DbConstants.tableProduct, {
      DbConstants.columnProductModel: 'PENDING',
      DbConstants.columnProductName: 'pending',
      DbConstants.columnUpdatedAt: 1000,
      DbConstants.columnIsDeleted: 0,
      DbConstants.columnRemoteId: null,
    });

    final n = await SyncMaintenance.backfillSeedOutbox(db);
    expect(n, 1);
    final ops = await outboxRows(db);
    expect(ops.first[DbConstants.columnPayload], contains('PENDING'));
  });

  test('seed then backfill finds nothing left to queue', () async {
    await DbSeeder.seedProducts(db);
    final afterSeed = await outboxRows(db);
    expect(afterSeed, hasLength(25));
    // backfill after seed should find 0 (already queued)
    final n = await SyncMaintenance.backfillSeedOutbox(db);
    expect(n, 0);
  });

  test('backfill returns 0 without throwing on a v1 database', () async {
    final v1 = await openV1Fixture();
    try {
      expect(await SyncMaintenance.backfillSeedOutbox(v1), 0);
    } finally {
      await v1.close();
    }
  });
}
