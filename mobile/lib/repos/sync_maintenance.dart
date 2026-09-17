import 'package:flutter/foundation.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:sqflite/sqflite.dart';

/// Result of the startup maintenance pass (Phase 5: bounded storage).
class MaintenanceSummary {
  final int tombstonesPurged;
  final int parkedEvicted;

  const MaintenanceSummary({this.tombstonesPurged = 0, this.parkedEvicted = 0});
}

/// Local counters for the settings screen (Phase 5 observability).
/// Engine-reported per-run up/down counts arrive separately via
/// `SyncTrigger.state` once the Phase 3 engine lands.
class SyncStats {
  final int pendingTotal;
  final int parkedTotal;
  final Map<String, int> pendingByTable;
  final String? firstParkedError;
  final DateTime? lastSyncAt;
  final int parkedEvictions;
  final int payloadWarnings;

  const SyncStats({
    this.pendingTotal = 0,
    this.parkedTotal = 0,
    this.pendingByTable = const {},
    this.firstParkedError,
    this.lastSyncAt,
    this.parkedEvictions = 0,
    this.payloadWarnings = 0,
  });
}

/// Phase 5 hardening that lives on the repo side of the seam:
///
/// * startup maintenance pass (tombstone purge > 30 days),
/// * dead-letter (parked) cap with oldest-first eviction + warning,
/// * read helpers feeding the settings counters.
///
/// Everything is defensive: missing tables/columns (v1 schema, parallel
/// Phase 2 work) yield zeros instead of crashes, and the maintenance pass
/// never throws.
class SyncMaintenance {
  SyncMaintenance._();

  /// Startup pass. Safe to call on a v1 database (no-ops gracefully).
  static Future<MaintenanceSummary> runStartupMaintenance(
    Database db, {
    DateTime? now,
  }) async {
    var purged = 0;
    var evicted = 0;
    try {
      purged = await purgeTombstones(db, now: now);
    } catch (e) {
      debugPrint('SyncMaintenance: tombstone purge skipped: $e');
    }
    try {
      evicted = await enforceParkedCap(db);
    } catch (e) {
      debugPrint('SyncMaintenance: parked-cap enforcement skipped: $e');
    }
    return MaintenanceSummary(tombstonesPurged: purged, parkedEvicted: evicted);
  }

  /// Deletes soft-deleted rows older than [DbConstants.tombstoneRetention].
  /// Returns the number of rows removed.
  static Future<int> purgeTombstones(
    DatabaseExecutor db, {
    DateTime? now,
  }) async {
    final cutoff =
        (now ?? DateTime.now()).millisecondsSinceEpoch -
        DbConstants.tombstoneRetention.inMilliseconds;
    var removed = 0;
    for (final table in DbConstants.syncedTables) {
      if (!await SyncMetadata.hasColumn(
        db,
        table,
        DbConstants.columnIsDeleted,
      )) {
        continue;
      }
      if (!await SyncMetadata.hasColumn(
        db,
        table,
        DbConstants.columnUpdatedAt,
      )) {
        continue;
      }
      removed += await db.delete(
        table,
        where:
            '${DbConstants.columnIsDeleted} = 1 AND ${DbConstants.columnUpdatedAt} < ?',
        whereArgs: [cutoff],
      );
    }
    if (removed > 0) {
      debugPrint('SyncMaintenance: purged $removed tombstone(s).');
    }
    return removed;
  }

  /// Caps parked (dead-letter) ops at [DbConstants.maxParkedOps],
  /// evicting oldest-first. Returns the number evicted.
  ///
  /// Parked = engine recorded a terminal failure (`last_error` set and
  /// attempts past the threshold). Until the Phase 3 engine lands this is
  /// normally zero; the helper is also exposed so the engine can call it
  /// after parking an op.
  static Future<int> enforceParkedCap(DatabaseExecutor db) async {
    if (!await SyncMetadata.hasTable(db, DbConstants.tableOutbox)) {
      return 0;
    }
    final countRows = await db.rawQuery('''
SELECT COUNT(*) AS c FROM ${DbConstants.tableOutbox}
WHERE ${DbConstants.columnLastError} IS NOT NULL
  AND ${DbConstants.columnAttempts} >= ${DbConstants.parkedAfterAttempts}''');
    final parked = (countRows.first['c'] as num?)?.toInt() ?? 0;
    final excess = parked - DbConstants.maxParkedOps;
    if (excess <= 0) return 0;

    // Single atomic statement: oldest-first via created_at ordering.
    final evicted = await db.delete(
      DbConstants.tableOutbox,
      where:
          '${DbConstants.columnOpId} IN (SELECT ${DbConstants.columnOpId} '
          'FROM ${DbConstants.tableOutbox} '
          'WHERE ${DbConstants.columnLastError} IS NOT NULL '
          'AND ${DbConstants.columnAttempts} >= ? '
          'ORDER BY ${DbConstants.columnCreatedAt} ASC LIMIT ?)',
      whereArgs: [DbConstants.parkedAfterAttempts, excess],
    );
    SyncTrigger.instance.counters.registerParkedEvictions(evicted);
    debugPrint(
      'SyncMaintenance: WARNING evicted $evicted oldest parked '
      'outbox op(s) (cap ${DbConstants.maxParkedOps}). '
      'Those operations will NOT sync; inspect device logs.',
    );
    return evicted;
  }

  /// Backfill: for existing installs that already have the 25 catalog rows
  /// but an empty outbox, create one `insert` outbox op per un-synced
  /// product row. Idempotent: re-running finds zero rows because
  /// `_id NOT IN (SELECT row_id FROM outbox WHERE table_name='product')`.
  ///
  /// Returns the number of ops enqueued. Never throws; missing
  /// tables/columns (v1 schema, fresh migration) yield 0.
  static Future<int> backfillSeedOutbox(Database db) async {
    try {
      if (!await SyncMetadata.hasTable(db, DbConstants.tableOutbox)) return 0;
      if (!await SyncMetadata.hasTable(db, DbConstants.tableProduct)) {
        return 0;
      }
      if (!await SyncMetadata.hasColumn(
        db,
        DbConstants.tableProduct,
        DbConstants.columnRemoteId,
      )) {
        return 0;
      }
      if (!await SyncMetadata.hasColumn(
        db,
        DbConstants.tableProduct,
        DbConstants.columnIsDeleted,
      )) {
        return 0;
      }
      // Single query per spec: un-synced, not deleted, not already queued.
      final rows = await db.rawQuery(
        '''
SELECT ${DbConstants.columnId} AS _id, ${DbConstants.columnProductModel} AS model
FROM ${DbConstants.tableProduct}
WHERE ${DbConstants.columnRemoteId} IS NULL
  AND ${DbConstants.columnIsDeleted} = 0
  AND ${DbConstants.columnId} NOT IN (
    SELECT ${DbConstants.columnRowId}
    FROM ${DbConstants.tableOutbox}
    WHERE ${DbConstants.columnTableName} = ?
  )
''',
        [DbConstants.tableProduct],
      );

      final ids = <int>[];
      final models = <int, String>{};
      for (final row in rows) {
        final id = row['_id'] as int?;
        final model = row['model'] as String?;
        if (id != null && model != null) {
          ids.add(id);
          models[id] = model;
        }
      }
      if (ids.isEmpty) return 0;
      // One transaction: all-or-none, one poke at the end via recordMutation.
      await db.transaction((txn) async {
        for (final id in ids) {
          // Same deterministic key as the seeder: converging, not duplicating.
          await SyncMetadata.recordMutation(
            txn,
            ref: MutationRef(
              table: DbConstants.tableProduct,
              rowId: id,
              op: DbConstants.opInsert,
            ),
            opIdOverride: DbConstants.seedOpId(
              DbConstants.tableProduct,
              models[id]!,
            ),
          );
        }
      });
      debugPrint(
        'SyncMaintenance: backfilled ${ids.length} seed outbox op(s).',
      );
      return ids.length;
    } catch (e) {
      debugPrint('SyncMaintenance: backfill skipped: $e');
      return 0;
    }
  }

  /// Reads local counters for settings. Never throws; missing schema
  /// yields a zero stat object.
  static Future<SyncStats> readStats(Database db) async {
    if (!await SyncMetadata.hasTable(db, DbConstants.tableOutbox)) {
      final counters = SyncTrigger.instance.counters;
      return SyncStats(
        parkedEvictions: counters.parkedEvictions,
        payloadWarnings: counters.payloadWarnings,
      );
    }
    int pending = 0;
    int parked = 0;
    final byTable = <String, int>{};
    String? firstError;
    try {
      final pendingRows = await db.rawQuery('''
SELECT ${DbConstants.columnTableName} AS t, COUNT(*) AS c
FROM ${DbConstants.tableOutbox}
GROUP BY ${DbConstants.columnTableName}''');
      for (final row in pendingRows) {
        final c = ((row['c'] as num?) ?? 0).toInt();
        byTable[(row['t'] as String?) ?? '?'] = c;
        pending += c;
      }
      final parkedRows = await db.rawQuery(
        '''
SELECT COUNT(*) AS c FROM ${DbConstants.tableOutbox}
WHERE ${DbConstants.columnLastError} IS NOT NULL
  AND ${DbConstants.columnAttempts} >= ?''',
        [DbConstants.parkedAfterAttempts],
      );
      parked = ((parkedRows.first['c'] as num?) ?? 0).toInt();
      if (parked > 0) {
        final errRows = await db.query(
          DbConstants.tableOutbox,
          columns: [
            DbConstants.columnLastError,
            DbConstants.columnTableName,
            DbConstants.columnRowId,
          ],
          where:
              '${DbConstants.columnLastError} IS NOT NULL AND ${DbConstants.columnAttempts} >= ?',
          whereArgs: [DbConstants.parkedAfterAttempts],
          orderBy: '${DbConstants.columnCreatedAt} ASC',
          limit: 1,
        );
        final err = errRows.first[DbConstants.columnLastError];
        firstError =
            '[${errRows.first[DbConstants.columnTableName]}:${errRows.first[DbConstants.columnRowId]}] $err';
      }
    } catch (e) {
      debugPrint('SyncMaintenance: stats read degraded: $e');
    }

    DateTime? lastSync;
    try {
      if (await SyncMetadata.hasTable(db, DbConstants.tableSyncState)) {
        final rows = await db.rawQuery('''
SELECT MAX(${DbConstants.columnLastPullAt}) AS m
FROM ${DbConstants.tableSyncState}''');
        final m = (rows.first['m'] as num?)?.toInt();
        if (m != null) {
          lastSync = DateTime.fromMillisecondsSinceEpoch(m);
        }
      }
    } catch (e) {
      debugPrint('SyncMaintenance: last-sync read degraded: $e');
    }

    final counters = SyncTrigger.instance.counters;
    return SyncStats(
      pendingTotal: pending,
      parkedTotal: parked,
      pendingByTable: byTable,
      firstParkedError: firstError,
      lastSyncAt: lastSync,
      parkedEvictions: counters.parkedEvictions,
      payloadWarnings: counters.payloadWarnings,
    );
  }
}
