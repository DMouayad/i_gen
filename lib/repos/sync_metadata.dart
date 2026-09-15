import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:sqflite/sqflite.dart';

/// Mechanical helpers used by every repository.
///
/// Schema/contract constants live in [DbConstants] (the single source of
/// truth — the v2 migration owns them). Session counters live on
/// [SyncTrigger.counters]. All methods degrade gracefully when the v2 schema
/// has not landed yet: stamps/filters are skipped, hard-delete fallbacks
/// apply, but outbox rows are still enqueued so no mutation is ever lost.
class SyncMetadata {
  SyncMetadata._();

  static int nowMillis() => DateTime.now().millisecondsSinceEpoch;

  static Future<bool> hasTable(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  static Future<bool> hasColumn(
    DatabaseExecutor db,
    String table,
    String column,
  ) async {
    if (!await hasTable(db, table)) return false;
    final info = await db.rawQuery('PRAGMA table_info($table)');
    return info.any((c) => c['name'] == column);
  }

  /// Creates the outbox table if the Phase 2 migration has not run yet.
  /// Idempotent: safe to call from every mutation.
  static Future<void> ensureOutboxTable(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS ${DbConstants.tableOutbox} (
  ${DbConstants.columnOpId} TEXT PRIMARY KEY,
  ${DbConstants.columnTableName} TEXT NOT NULL,
  ${DbConstants.columnRowId} INTEGER NOT NULL,
  ${DbConstants.columnOp} TEXT NOT NULL,
  ${DbConstants.columnPayload} TEXT NOT NULL,
  ${DbConstants.columnCreatedAt} INTEGER NOT NULL,
  ${DbConstants.columnAttempts} INTEGER NOT NULL DEFAULT 0,
  ${DbConstants.columnLastError} TEXT
)''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_outbox_created
ON ${DbConstants.tableOutbox} (${DbConstants.columnCreatedAt})''');
  }

  /// Returns a copy of [values] with `updated_at = now` when the column
  /// exists (v2 schema), otherwise the original map untouched.
  static Future<Map<String, Object?>> withStamp(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> values,
  ) async {
    if (await hasColumn(db, table, DbConstants.columnUpdatedAt)) {
      return {...values, DbConstants.columnUpdatedAt: nowMillis()};
    }
    return values;
  }

  /// `WHERE` fragment hiding soft-deleted rows, or `1 = 1` on a v1 schema.
  static Future<String> notDeletedClause(
    DatabaseExecutor db,
    String table, {
    String? alias,
  }) async {
    if (await hasColumn(db, table, DbConstants.columnIsDeleted)) {
      return '${alias ?? table}.${DbConstants.columnIsDeleted} = 0';
    }
    return '1 = 1';
  }

  static Future<Map<String, Object?>?> _fetchRow(
    DatabaseExecutor db,
    String table,
    int rowId,
  ) async {
    final rows = await db.query(
      table,
      where: '_id = ?',
      whereArgs: [rowId],
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  /// Enqueues exactly one outbox op for a mutation, inside the caller's
  /// transaction when given one (all-or-none with the row write). Must be
  /// called AFTER the row write (or delete) so the payload reflects the new
  /// state.
  ///
  /// Never throws for sync reasons: if the payload cannot be read, a
  /// minimal `{'_id': rowId}` payload is queued so the engine still learns
  /// the row changed.
  static Future<String> recordMutation(
    DatabaseExecutor db, {
    required MutationRef ref,
    Map<String, Object?>? payloadOverride,
  }) async {
    await ensureOutboxTable(db);
    Map<String, Object?> payload;
    try {
      payload =
          payloadOverride ??
          await _fetchRow(db, ref.table, ref.rowId) ??
          {'_id': ref.rowId};
    } catch (_) {
      payload = {'_id': ref.rowId};
    }

    String encoded;
    try {
      encoded = jsonEncode(payload);
    } catch (_) {
      encoded = jsonEncode({'_id': ref.rowId});
    }
    if (utf8.encode(encoded).length > DbConstants.payloadWarnBytes) {
      SyncTrigger.instance.counters.registerPayloadWarning();
      debugPrint(
        'SyncMetadata: payload for ${ref.table}:${ref.rowId} exceeds '
        '${DbConstants.payloadWarnBytes} bytes (op=${ref.op}). '
        'Large payloads sync slowly; see Phase 5 payload guard.',
      );
    }

    final opId = DbConstants.newOpId();
    await db.insert(DbConstants.tableOutbox, {
      DbConstants.columnOpId: opId,
      DbConstants.columnTableName: ref.table,
      DbConstants.columnRowId: ref.rowId,
      DbConstants.columnOp: ref.op,
      DbConstants.columnPayload: encoded,
      DbConstants.columnCreatedAt: nowMillis(),
      DbConstants.columnAttempts: 0,
      DbConstants.columnLastError: null,
    });

    // Debounced auto-push (~2s) via the trigger; the engine registers its
    // public syncNow() there. Repos never import the engine.
    SyncTrigger.instance.poke();
    return opId;
  }

  /// Soft-deletes a row (`is_deleted = 1`, bumps `updated_at`) when the v2
  /// columns exist; otherwise falls back to a hard delete so behavior on
  /// a v1 schema is unchanged. Returns the pre-delete row (if any) for
  /// use as the outbox payload.
  static Future<Map<String, Object?>?> softDelete(
    Transaction txn,
    String table,
    int rowId,
  ) async {
    final before = await _fetchRow(txn, table, rowId);
    if (await hasColumn(txn, table, DbConstants.columnIsDeleted)) {
      final values = <String, Object?>{DbConstants.columnIsDeleted: 1};
      if (await hasColumn(txn, table, DbConstants.columnUpdatedAt)) {
        values[DbConstants.columnUpdatedAt] = nowMillis();
      }
      await txn.update(table, values, where: '_id = ?', whereArgs: [rowId]);
    } else {
      await txn.delete(table, where: '_id = ?', whereArgs: [rowId]);
    }
    return before;
  }
}
