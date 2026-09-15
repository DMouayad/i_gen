import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/db.dart';
import 'test_helper.dart';

void main() {
  test('v1 -> v2 upgrade preserves rows and backfills sync metadata', () async {
    final v1 = await openV1Fixture();
    final path = v1.path;
    final before = <String, int>{};
    for (final table in DbConstants.syncedTables) {
      before[table] = await tableCount(v1, table);
    }
    expect(before.values.every((c) => c > 0), isTrue);
    await v1.close();

    final db = await reopenViaProvider(path);

    // Row counts identical on all five business tables.
    for (final table in DbConstants.syncedTables) {
      expect(await tableCount(db, table), before[table], reason: table);
    }
    // remote_id stays null (first sync pushes everything as inserts),
    // updated_at backfilled, is_deleted defaults to 0.
    for (final table in DbConstants.syncedTables) {
      final rows = await db.query(table);
      expect(rows, isNotEmpty, reason: table);
      for (final row in rows) {
        expect(row[DbConstants.columnRemoteId], isNull, reason: table);
        expect(row[DbConstants.columnUpdatedAt], isNotNull, reason: table);
        expect(row[DbConstants.columnIsDeleted], 0, reason: table);
      }
    }
    // Bookkeeping tables exist and start empty.
    expect(await tableCount(db, DbConstants.tableOutbox), 0);
    expect(await tableCount(db, DbConstants.tableSyncState), 0);
    await db.close();
  });

  test('fresh-install schema equals upgraded schema', () async {
    final v1 = await openV1Fixture();
    final path = v1.path;
    await v1.close();
    final upgraded = await reopenViaProvider(path);
    final fresh = await openFreshTestDb();

    Future<Map<String, List<String>>> describe(Database db) async {
      final out = <String, List<String>>{};
      final tables = await db.rawQuery(
        "SELECT name, sql FROM sqlite_master WHERE type IN ('table','index') "
        "AND name NOT LIKE 'sqlite_%' "
        'ORDER BY name',
      );
      for (final t in tables) {
        out['${t['type']}:${t['name']}'] = [t['sql'] as String? ?? ''];
      }
      for (final table in [
        ...DbConstants.syncedTables,
        DbConstants.tableOutbox,
        DbConstants.tableSyncState,
      ]) {
        final cols = await db.rawQuery('PRAGMA table_info($table)');
        out['cols:$table'] = [
          for (final c in cols)
            '${c['name']}:${c['type']}:${c['notnull']}:${c['dflt_value']}:${c['pk']}',
        ];
      }
      return out;
    }

    // Both schemas are built by the same migration code, so they must be
    // identical (tables, columns, and indexes).
    expect(await describe(fresh), await describe(upgraded));
    await upgraded.close();
    await fresh.close();
  });

  test('outbox preserves FIFO order under interleaved writes', () async {
    final db = await openFreshTestDb();
    var tick = 1000;
    Future<void> enqueue(String table, int rowId, String op) =>
        db.insert(DbConstants.tableOutbox, {
          DbConstants.columnOpId: 'op-${tick++}',
          DbConstants.columnTableName: table,
          DbConstants.columnRowId: rowId,
          DbConstants.columnOp: op,
          DbConstants.columnPayload: '{}',
          DbConstants.columnCreatedAt: tick,
          DbConstants.columnAttempts: 0,
        });

    // Interleave tables and op kinds; FIFO must follow created_at globally,
    // and per-table filtering must keep each table's relative order.
    await enqueue(DbConstants.tableInvoice, 1, DbConstants.opInsert);
    await enqueue(DbConstants.tableProduct, 1, DbConstants.opInsert);
    await enqueue(DbConstants.tableInvoice, 1, DbConstants.opUpdate);
    await enqueue(DbConstants.tableProduct, 2, DbConstants.opInsert);
    await enqueue(DbConstants.tableInvoice, 2, DbConstants.opDelete);

    final all = await db.query(
      DbConstants.tableOutbox,
      orderBy: '${DbConstants.columnCreatedAt} ASC',
    );
    expect(
      [for (final o in all) o[DbConstants.columnOpId]],
      ['op-1000', 'op-1001', 'op-1002', 'op-1003', 'op-1004'],
    );

    final invoices = await db.query(
      DbConstants.tableOutbox,
      where: '${DbConstants.columnTableName} = ?',
      whereArgs: [DbConstants.tableInvoice],
      orderBy: '${DbConstants.columnCreatedAt} ASC',
    );
    expect(
      [for (final o in invoices) o[DbConstants.columnOp]],
      [DbConstants.opInsert, DbConstants.opUpdate, DbConstants.opDelete],
    );
    await db.close();
  });
}
