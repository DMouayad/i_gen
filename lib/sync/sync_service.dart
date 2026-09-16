import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

// ignore_for_file: prefer_initializing_formals
// Reason: public parameter names (db/remote/auth) must stay stable for the
// repo-wiring agent while the backing fields are private (_db/_remote/_auth).

import 'package:sqflite/sqflite.dart';

import 'package:i_gen/db.dart';
import 'package:i_gen/repos/sync_trigger.dart' as ui;
import 'auth_info.dart';
import 'remote_gateway.dart';

/// Overall sync state for the settings UI (Phase 4 surface).
enum SyncState { idle, syncing, success, error }

/// Point-in-time snapshot of sync health: last sync time plus per-table
/// push/pull counters for the most recent run, and the parked-op error.
class SyncStatus {
  const SyncStatus({
    required this.state,
    this.lastSyncAt,
    this.pushedPerTable = const {},
    this.pulledPerTable = const {},
    this.lastError,
  });

  final SyncState state;
  final DateTime? lastSyncAt;
  final Map<String, int> pushedPerTable;
  final Map<String, int> pulledPerTable;

  /// Human-readable error of the most recent failure / parked op, if any.
  final String? lastError;

  int get pushedTotal => pushedPerTable.values.fold(0, (a, b) => a + b);
  int get pulledTotal => pulledPerTable.values.fold(0, (a, b) => a + b);
}

/// Outcome of one [SyncService.syncNow] run.
class SyncResult {
  const SyncResult._({
    required this.synced,
    required this.skippedUnauthenticated,
    required this.pushedPerTable,
    required this.pulledPerTable,
    this.error,
  });

  factory SyncResult.ok({
    Map<String, int> pushedPerTable = const {},
    Map<String, int> pulledPerTable = const {},
  }) => SyncResult._(
    synced: true,
    skippedUnauthenticated: false,
    pushedPerTable: pushedPerTable,
    pulledPerTable: pulledPerTable,
  );

  factory SyncResult.failed(
    String error, {
    Map<String, int> pushedPerTable = const {},
    Map<String, int> pulledPerTable = const {},
  }) => SyncResult._(
    synced: false,
    skippedUnauthenticated: false,
    pushedPerTable: pushedPerTable,
    pulledPerTable: pulledPerTable,
    error: error,
  );

  factory SyncResult.skippedUnauthenticated() => const SyncResult._(
    synced: false,
    skippedUnauthenticated: true,
    pushedPerTable: {},
    pulledPerTable: {},
  );

  /// True when the run completed (even with per-op failures parked).
  /// False only when skipped (logged out) — never throws for remote errors.
  final bool synced;
  final bool skippedUnauthenticated;
  final Map<String, int> pushedPerTable;
  final Map<String, int> pulledPerTable;
  final String? error;
}

/// Hand-rolled outbox + delta-pull sync engine (Phase 3 spec).
///
/// Push first (outbox FIFO, idempotent via client `op_id`, `remote_id`
/// written back on ack), then pull per-table deltas (`updated_at` anchors in
/// `sync_state`, last-write-wins merge, remote tombstones hard-delete
/// locally). Each table syncs inside its own local transaction so one
/// table's failure never corrupts another, and no local transaction spans
/// the network: every remote call is one statement, local commits are
/// separate transactions.
class SyncService {
  SyncService({
    required Database db,
    required RemoteGateway remote,
    required AuthInfoProvider auth,
    this.maxAttempts = DbConstants.parkedAfterAttempts,
    this.backoffBase = const Duration(seconds: 1),
    this.maxBackoff = const Duration(minutes: 5),
    this.autoPushDebounce = const Duration(seconds: 2),
  }) : _db = db,
       _remote = remote,
       _auth = auth;

  final Database _db;
  final RemoteGateway _remote;
  final AuthInfoProvider _auth;

  /// After [maxAttempts] failures an op is parked (kept with `last_error`,
  /// skipped by future pushes) instead of blocking the queue behind it.
  /// Defaults to [DbConstants.parkedAfterAttempts] — the same constant the
  /// maintenance cap reads, so the two can never disagree.
  final int maxAttempts;

  /// Per-op exponential backoff: retry delay is
  /// `min(backoffBase * 2^(attempts-1), maxBackoff)`, tracked in memory per
  /// `op_id` (attempt counts persist in the outbox). Injectable for tests.
  final Duration backoffBase;
  final Duration maxBackoff;

  /// Debounce for [notifyWrite]: a sync fires this long after the last
  /// local write instead of on every keystroke.
  final Duration autoPushDebounce;

  /// Child table → {local FK column → parent local table}. Used to swap
  /// local integer ids for parent `remote_id`s on upload and back on pull.
  static const Map<String, Map<String, String>> fkParents = {
    DbConstants.tableInvoiceLine: {
      DbConstants.columnInvoiceLineInvoiceId: DbConstants.tableInvoice,
      DbConstants.columnInvoiceLineProductId: DbConstants.tableProduct,
    },
    DbConstants.tablePrices: {
      DbConstants.columnPricesProductId: DbConstants.tableProduct,
      DbConstants.columnPricesPriceCategoryId: DbConstants.tablePriceCategory,
    },
  };

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  /// UI stream: `lastSyncAt` + per-table counters + error display.
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus _current = const SyncStatus(state: SyncState.idle);
  SyncStatus get currentStatus => _current;

  DateTime? _lastSyncAt;
  DateTime? get lastSyncAt => _lastSyncAt;

  Future<SyncResult>? _inflight;
  Timer? _debounce;
  final Map<String, int> _notBeforeMillis = {};
  bool _disposed = false;

  void _emit(SyncStatus status) {
    _current = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// No-op until the wiring agent subscribes connectivity/app-lifecycle
  /// sources to [handleConnectivityRegained]/[handleAppResumed]. Kept so
  /// engine construction has a symmetric lifecycle with [dispose].
  Future<void> start() async {}

  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    await _statusController.close();
  }

  /// Entry point for manual sync ("Sync now" button), retry triggers, and
  /// the automatic triggers below. Coalesces overlapping calls into one run.
  /// Never throws for remote failures — they are parked with `last_error`.
  /// Returns [SyncResult.skippedUnauthenticated] while logged out.
  Future<SyncResult> syncNow() {
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final future = _runSync();
    _inflight = future;
    future.whenComplete(() {
      if (identical(_inflight, future)) _inflight = null;
    });
    return future;
  }

  /// Call after every local write (Phase 4 wiring). Debounced (~2s) so a
  /// burst of edits triggers one push, not one per keystroke.
  void notifyWrite() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(autoPushDebounce, () {
      if (!_disposed) unawaited(syncNow());
    });
  }

  /// Wiring-agent hook: subscribe the `connectivity_plus` stream and call
  /// this when connectivity is regained (offline → online transition).
  Future<SyncResult> handleConnectivityRegained() => syncNow();

  /// Wiring-agent hook: call from a `WidgetsBindingObserver.didChangeAppLifecycleState`
  /// `resumed` callback.
  Future<SyncResult> handleAppResumed() => syncNow();

  /// Clears backoff + parked state (`attempts`, `last_error`) for parked ops
  /// and runs a sync. Surfaced in settings next to the parked error.
  Future<SyncResult> retryParked() async {
    _notBeforeMillis.clear();
    await _db.update(
      DbConstants.tableOutbox,
      {DbConstants.columnAttempts: 0, DbConstants.columnLastError: null},
      where: '${DbConstants.columnAttempts} >= ?',
      whereArgs: [maxAttempts],
    );
    return syncNow();
  }

  // ---------------------------------------------------------------- run ---

  Future<SyncResult> _runSync() async {
    final ownerId = _auth.ownerId;
    if (ownerId == null) {
      // Logged out: nothing to do, and lastSyncAt must NOT advance (a
      // manual tap would otherwise stamp a fresh "synced" time for a run
      // that synced nothing — SyncTrigger only stamps when still syncing,
      // so publishing the unchanged state here holds the line).
      try {
        ui.SyncTrigger.instance.report(
          ui.SyncTrigger.instance.state.value.copyWith(
            status: ui.SyncStatus.synced,
            clearError: true,
            uploadedByTable: const {},
            downloadedByTable: const {},
            skippedByTable: const {},
          ),
        );
      } catch (_) {}
      return SyncResult.skippedUnauthenticated();
    }

    _emit(
      SyncStatus(
        state: SyncState.syncing,
        lastSyncAt: _lastSyncAt,
        lastError: _current.lastError,
      ),
    );

    final pushed = <String, int>{};
    final pulled = <String, int>{};
    final skipped = <String, int>{};
    final errors = <String>[];

    for (final table in SyncTables.orderedLocalTables) {
      _PushOutcome push;
      try {
        push = await _pushTable(table, ownerId);
      } catch (e) {
        // Defensive: _pushTable already isolates per-op failures; this only
        // guards against unexpected table-wide errors so other tables still
        // sync (partial-failure atomicity per table).
        errors.add('$table push: $e');
        continue;
      }
      pushed[table] = push.acked;
      // NOTE: a failed push neither fails the run nor skips the pull.
      // Per-op failures are transient and invisible (recorded with
      // attempts/last_error, retried later, surfaced only when parked);
      // downloads must not wait for uploads.
      try {
        final pull = await _pullTable(table, ownerId);
        pulled[table] = pull.merged;
        if (pull.skipped > 0) skipped[table] = pull.skipped;
      } catch (e) {
        errors.add('$table pull: $e');
      }
    }

    final parkedError = await _parkedError();
    final problems = [...errors];
    if (parkedError != null) problems.add(parkedError);
    final lastError = problems.isEmpty ? null : problems.join('; ');
    _lastSyncAt = DateTime.now();
    _emit(
      SyncStatus(
        state: lastError == null ? SyncState.success : SyncState.error,
        lastSyncAt: _lastSyncAt,
        pushedPerTable: pushed,
        pulledPerTable: pulled,
        lastError: lastError,
      ),
    );
    // Publish per-table up/down/skip counters + errors to the settings UI.
    // Never throws: observability must not break sync.
    try {
      ui.SyncTrigger.instance.report(
        ui.SyncTrigger.instance.state.value.copyWith(
          status: lastError == null
              ? ui.SyncStatus.synced
              : ui.SyncStatus.error,
          lastSyncAt: _lastSyncAt,
          lastError: lastError,
          clearError: lastError == null,
          uploadedByTable: pushed,
          downloadedByTable: pulled,
          skippedByTable: skipped,
        ),
      );
    } catch (_) {}

    if (lastError == null) {
      return SyncResult.ok(pushedPerTable: pushed, pulledPerTable: pulled);
    }
    return SyncResult.failed(
      lastError,
      pushedPerTable: pushed,
      pulledPerTable: pulled,
    );
  }

  // --------------------------------------------------------------- push ---

  /// Pushes one table's outbox ops, oldest first. Per-op failures bump
  /// `attempts`/`last_error` and never abort the table; ops at [maxAttempts]
  /// are parked (skipped, surfaced via status stream). Transient failures are
  /// otherwise invisible (retried on a later run, per the offline-first spec).
  Future<_PushOutcome> _pushTable(String table, String ownerId) async {
    var acked = 0;
    var hadFailure = false;
    // One attempt per op per run: ops that fail are recorded and retried on
    // a later run (after backoff), never spun in this run's passes. Passes
    // exist only so children deferred on a missing parent remote_id retry
    // after their parents upload in the same run.
    final failedThisRun = <String>{};
    // Multiple passes so children whose parents had no remote_id yet
    // (deferred) get retried after their parents upload in the same run.
    for (var pass = 0; pass < SyncTables.orderedLocalTables.length; pass++) {
      final ops = await _db.query(
        DbConstants.tableOutbox,
        where:
            '${DbConstants.columnTableName} = ? '
            'AND ${DbConstants.columnAttempts} < ?',
        whereArgs: [table, maxAttempts],
        orderBy: '${DbConstants.columnCreatedAt} ASC',
      );
      var progress = false;
      for (final op in ops) {
        final opId = op[DbConstants.columnOpId] as String;
        if (failedThisRun.contains(opId) || _inBackoff(opId)) continue;
        final outcome = await _pushOp(table, op, ownerId);
        if (outcome == _OpOutcome.acked) {
          acked++;
          progress = true;
        } else if (outcome == _OpOutcome.deferred) {
          // Parent remote_id missing; a later pass (or later sync) retries.
          continue;
        } else {
          failedThisRun.add(opId);
          hadFailure = true;
        }
      }
      if (!progress) break;
    }
    return (acked: acked, hadFailure: hadFailure);
  }

  Future<_OpOutcome> _pushOp(
    String table,
    Map<String, dynamic> op,
    String ownerId,
  ) async {
    final opId = op[DbConstants.columnOpId] as String;
    final opKind = op[DbConstants.columnOp] as String;
    final rowId = op[DbConstants.columnRowId] as int;
    final remoteTable = SyncTables.remoteFor(table);

    try {
      final localRows = await _db.query(
        table,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [rowId],
        limit: 1,
      );

      if (opKind == DbConstants.opDelete) {
        await _pushDeleteOp(
          table,
          remoteTable,
          opId,
          rowId,
          ownerId,
          localRows.isEmpty ? null : localRows.first,
        );
        return _OpOutcome.acked;
      }

      if (localRows.isEmpty) {
        // Row is gone (hard-deleted locally); nothing to upload.
        await _deleteOp(opId);
        return _OpOutcome.acked;
      }
      final local = localRows.first;
      final upload = await _toRemoteRow(table, local);
      if (upload == null) return _OpOutcome.deferred;

      final remoteId = local[DbConstants.columnRemoteId] as String?;
      final result = await _remote.upsertRow(
        remoteTable: remoteTable,
        row: upload,
        remoteId: remoteId,
        ownerId: ownerId,
        opId: opId,
      );
      // Ack: write back remote_id (+ server timestamp to avoid pull churn)
      // and delete the op in ONE local transaction — atomic, so a crash
      // between server-ack and here replays via the op_id idempotency key.
      await _db.transaction((txn) async {
        await txn.update(
          table,
          {
            DbConstants.columnRemoteId: result.id,
            DbConstants.columnUpdatedAt: result.updatedAtMillis,
          },
          where: '${DbConstants.columnId} = ?',
          whereArgs: [rowId],
        );
        await txn.delete(
          DbConstants.tableOutbox,
          where: '${DbConstants.columnOpId} = ?',
          whereArgs: [opId],
        );
      });
      _notBeforeMillis.remove(opId);
      return _OpOutcome.acked;
    } catch (e) {
      // Best-effort seed pushes refused by role policy (e.g. employee hits
      // the catalog admin_write rule) are dropped, not parked: the device
      // converges onto the admin's uuids via pull, and parking 25
      // unfixable ops would paint every non-admin device red forever.
      if (DbConstants.isSeedOpId(table, opId) && _isPermissionDenied('$e')) {
        await _deleteOp(opId);
        return _OpOutcome.failed;
      }
      await _recordOpFailure(opId, '$e');
      return _OpOutcome.failed;
    }
  }

  Future<void> _pushDeleteOp(
    String table,
    String remoteTable,
    String opId,
    int rowId,
    String ownerId,
    Map<String, dynamic>? local,
  ) async {
    final remoteId = local?[DbConstants.columnRemoteId] as String?;
    if (remoteId != null) {
      // Server confirms the tombstone first; only then hard-delete locally.
      await _remote.deleteRow(
        remoteTable: remoteTable,
        remoteId: remoteId,
        ownerId: ownerId,
        opId: opId,
      );
    }
    // Never synced (no remote twin) → nothing to tell the server.
    await _db.transaction((txn) async {
      await txn.delete(
        table,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [rowId],
      );
      await txn.delete(
        DbConstants.tableOutbox,
        where: '${DbConstants.columnOpId} = ?',
        whereArgs: [opId],
      );
    });
    _notBeforeMillis.remove(opId);
  }

  /// Builds the server-bound row: business columns with local FK ids swapped
  /// for parent `remote_id`s. Returns null when a parent has no `remote_id`
  /// yet (caller defers the op until the parent uploads).
  Future<Map<String, dynamic>?> _toRemoteRow(
    String table,
    Map<String, dynamic> local,
  ) async {
    final out = <String, dynamic>{};
    final fks = fkParents[table] ?? const {};
    for (final entry in local.entries) {
      final key = entry.key;
      if (key == DbConstants.columnId ||
          key == DbConstants.columnRemoteId ||
          key == DbConstants.columnUpdatedAt) {
        continue;
      }
      if (key == DbConstants.columnIsDeleted) continue; // upserts are live
      if (fks.containsKey(key)) {
        final parentTable = fks[key]!;
        final parentLocalId = entry.value as int?;
        if (parentLocalId == null) return null;
        final parentRemoteId = await _remoteIdOf(parentTable, parentLocalId);
        if (parentRemoteId == null) return null; // parent not pushed yet
        out[key] = parentRemoteId;
      } else {
        out[key] = entry.value;
      }
    }
    return out;
  }

  Future<String?> _remoteIdOf(String table, int localId) async {
    final rows = await _db.query(
      table,
      columns: [DbConstants.columnRemoteId],
      where: '${DbConstants.columnId} = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first[DbConstants.columnRemoteId] as String?;
  }

  Future<void> _deleteOp(String opId) async {
    await _db.delete(
      DbConstants.tableOutbox,
      where: '${DbConstants.columnOpId} = ?',
      whereArgs: [opId],
    );
    _notBeforeMillis.remove(opId);
  }

  Future<void> _recordOpFailure(String opId, String error) async {
    final rows = await _db.query(
      DbConstants.tableOutbox,
      columns: [DbConstants.columnAttempts],
      where: '${DbConstants.columnOpId} = ?',
      whereArgs: [opId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final attempts =
        ((rows.first[DbConstants.columnAttempts] as int?) ?? 0) + 1;
    await _db.update(
      DbConstants.tableOutbox,
      {
        DbConstants.columnAttempts: attempts,
        DbConstants.columnLastError: error,
      },
      where: '${DbConstants.columnOpId} = ?',
      whereArgs: [opId],
    );
    if (attempts < maxAttempts) {
      final shift = (attempts - 1).clamp(0, 20);
      var delay = backoffBase * (1 << shift);
      if (delay > maxBackoff) delay = maxBackoff;
      _notBeforeMillis[opId] =
          DateTime.now().millisecondsSinceEpoch + delay.inMilliseconds;
    }
    // At the cap the op stays parked with last_error, skipped by _pushTable.
  }

  /// True when a push error is a role-policy refusal rather than a
  /// transient failure: PostgREST 42501 ("permission denied"), RLS policy
  /// violations, and test-fake equivalents. Matched loosely on purpose —
  /// supabase_flutter surfaces these as PostgrestException text.
  static bool _isPermissionDenied(String error) {
    final lower = error.toLowerCase();
    return lower.contains('42501') ||
        lower.contains('permission denied') ||
        lower.contains('row-level security') ||
        lower.contains('rls denied');
  }

  bool _inBackoff(String opId) {
    final notBefore = _notBeforeMillis[opId];
    if (notBefore == null) return false;
    if (DateTime.now().millisecondsSinceEpoch >= notBefore) {
      _notBeforeMillis.remove(opId);
      return false;
    }
    return true;
  }

  // --------------------------------------------------------------- pull ---

  /// Pulls one table's delta and merges it (LWW). Returns merged/skip counts.
  /// The `sync_state` checkpoint advances only after the merge transaction
  /// commits, and only over rows actually pulled.
  Future<({int merged, int skipped})> _pullTable(
    String table,
    String ownerId,
  ) async {
    final lastPull = await _lastPullAt(table);
    final remoteTable = SyncTables.remoteFor(table);
    final rows = await _remote.pullTable(
      remoteTable: remoteTable,
      ownerId: ownerId,
      lastPullAtMillis: lastPull,
    );
    if (rows.isEmpty) return (merged: 0, skipped: 0);

    final localColumns = await _localColumns(table);
    var maxPulledAt = lastPull;
    var merged = 0;
    var skipped = 0;
    int? minSkippedAt;

    await _db.transaction((txn) async {
      for (final remote in rows) {
        final id = remote['id'] as String?;
        if (id == null) continue;
        final remoteAt = asMillis(remote['updated_at']);
        final deleted = asBool(remote['is_deleted']);
        final outcome = await _mergeRow(
          txn,
          table,
          localColumns,
          id,
          remote,
          remoteAt,
          deleted,
        );
        if (outcome) {
          merged++;
        } else {
          // Skipped (orphan child, stale LWW loser): counted and retried,
          // never silently dropped (see checkpoint rule below).
          skipped++;
          if (minSkippedAt == null || remoteAt < minSkippedAt!) {
            minSkippedAt = remoteAt;
          }
          continue;
        }
        // Advance only over merged rows OLDER than every skip: jumping past
        // an older orphan would exclude it from the next delta forever.
        final heldAt = minSkippedAt;
        if (heldAt != null && remoteAt >= heldAt) continue;
        final checkpoint = maxPulledAt;
        if (checkpoint == null || remoteAt > checkpoint) {
          maxPulledAt = remoteAt;
        }
      }
    });
    if (skipped > 0) {
      debugPrint(
        'SyncService: $table pull skipped $skipped row(s); '
        'checkpoint held at $maxPulledAt for retry.',
      );
    }

    // Checkpoint advances only after the merge transaction commits.
    if (maxPulledAt != null && maxPulledAt != lastPull) {
      await _db.insert(DbConstants.tableSyncState, {
        DbConstants.columnTableName: table,
        DbConstants.columnLastPullAt: maxPulledAt,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return (merged: merged, skipped: skipped);
  }

  /// Merges one remote row. Returns true when the local store changed.
  /// Remote tombstones hard-delete the local row and clear its queued ops.
  /// Otherwise last-write-wins on `updated_at` (remote wins strictly when
  /// newer; ties/local-newer keep local).
  Future<bool> _mergeRow(
    Transaction txn,
    String table,
    Set<String> localColumns,
    String id,
    Map<String, dynamic> remote,
    int remoteAt,
    bool deleted,
  ) async {
    // Pull-side ack recovery: the row carries our own `client_op_id` and the
    // op is still queued, meaning a previous delivery applied server-side but
    // the ack never landed (crash between server-ack and op-delete). Adopt
    // the server id/timestamp and drop the op instead of inserting a
    // duplicate — this is what makes always-pull safe.
    final clientOpId = remote['client_op_id'] as String?;
    if (clientOpId != null && !deleted) {
      if (await _recoverOwnUpload(txn, table, id, remoteAt, clientOpId)) {
        return true;
      }
    }

    final existing = await txn.query(
      table,
      where: '${DbConstants.columnRemoteId} = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (deleted) {
      if (existing.isEmpty) return false;
      final rowId = existing.first[DbConstants.columnId] as int;
      await txn.delete(
        table,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [rowId],
      );
      await txn.delete(
        DbConstants.tableOutbox,
        where:
            '${DbConstants.columnTableName} = ? '
            'AND ${DbConstants.columnRowId} = ?',
        whereArgs: [table, rowId],
      );
      return true;
    }

    final values = await _toLocalValues(txn, table, localColumns, remote);
    if (values == null) return false; // orphan child (parent unknown); skip.
    values[DbConstants.columnRemoteId] = id;
    values[DbConstants.columnUpdatedAt] = remoteAt;
    values[DbConstants.columnIsDeleted] = 0;

    if (existing.isEmpty) {
      // No row with this server id. Catalog tables carry a natural key
      // (product.model, price_category.name) that survives multi-device
      // seeding: a twin row with a different server id must converge
      // update-in-place instead of throwing the whole table pull away on
      // UNIQUE(model/name). Without this, one conflicting row aborts the
      // entire transaction and starves dependent tables (prices).
      final twin = await _findNaturalTwin(txn, table, remote);
      if (twin == null) {
        await txn.insert(table, values);
        return true;
      }
      final twinId = twin[DbConstants.columnId] as int;
      final localAt = (twin[DbConstants.columnUpdatedAt] as int?) ?? 0;
      if (remoteAt > localAt) {
        // Newer twin: merge everything. Adopt the pulled server id when
        // the local row was never synced (it has no twin of its own);
        // otherwise keep the local id — the server holds duplicates and
        // picking a winner locally cannot heal that (one-time server
        // dedupe finishes the job). (values already carries the pulled
        // id; drop it to keep the local one.)
        if (twin[DbConstants.columnRemoteId] == null) {
          values[DbConstants.columnRemoteId] = id;
        } else {
          values.remove(DbConstants.columnRemoteId);
        }
        await txn.update(
          table,
          values,
          where: '${DbConstants.columnId} = ?',
          whereArgs: [twinId],
        );
      } else if (twin[DbConstants.columnRemoteId] == null) {
        // Older twin, but the local row was never synced: adopt the server
        // identity anyway (nothing depends on the local id yet) while
        // keeping the newer local content. This is what lets a device that
        // could never push (e.g. employee, catalog writes are admin-only)
        // converge onto the admin's uuids so prices resolve.
        await txn.update(
          table,
          {DbConstants.columnRemoteId: id},
          where: '${DbConstants.columnId} = ?',
          whereArgs: [twinId],
        );
      }
      // Converged (or already current): processed, not skipped, so the
      // checkpoint advances instead of retrying forever.
      return true;
    }
    final localAt = (existing.first[DbConstants.columnUpdatedAt] as int?) ?? 0;
    if (remoteAt > localAt) {
      final rowId = existing.first[DbConstants.columnId] as int;
      await txn.update(
        table,
        values,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [rowId],
      );
      return true;
    }
    // Same-millisecond tie on the same server row (e.g. rows just pushed by
    // this device and re-pulled on a first sync with no checkpoint yet):
    // ties keep local content AND count as processed so the checkpoint
    // advances instead of re-pulling the same rows on every run. The residual
    // risk (two writers, same row, same millisecond, different content —
    // the later write is dropped) is negligible next to permanent re-pull
    // noise; server timestamps keep microsecond precision.
    if (remoteAt == localAt) return true;
    return false;
  }

  /// Finds a local row with the same natural key as a pulled row that has
  /// no `remote_id` match. Only catalog tables have natural keys
  /// (`product.model`, `price_category.name`); every other table returns
  /// null and takes the plain insert path. Tombstones never take this path
  /// (handled by the caller): a delete for one server id must not remove a
  /// local twin that maps to a different, still-live server row.
  Future<Map<String, Object?>?> _findNaturalTwin(
    Transaction txn,
    String table,
    Map<String, dynamic> remote,
  ) async {
    final String keyColumn;
    final Object? keyValue;
    if (table == DbConstants.tableProduct) {
      keyColumn = DbConstants.columnProductModel;
      keyValue = remote[keyColumn];
    } else if (table == DbConstants.tablePriceCategory) {
      keyColumn = DbConstants.columnPriceCategoryName;
      keyValue = remote[keyColumn];
    } else {
      return null;
    }
    if (keyValue == null) return null;
    final rows = await txn.query(
      table,
      where: '$keyColumn = ?',
      whereArgs: [keyValue],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Pull-side ack recovery (see [_mergeRow]): matches a pulled row's
  /// `client_op_id` against the still-queued outbox op, writes the server
  /// id/timestamp back onto the local row, and drops the op — atomically.
  /// Returns false when no queued op carries [clientOpId] (normal row).
  Future<bool> _recoverOwnUpload(
    Transaction txn,
    String table,
    String serverId,
    int remoteAt,
    String clientOpId,
  ) async {
    final ops = await txn.query(
      DbConstants.tableOutbox,
      columns: [DbConstants.columnRowId],
      where: '${DbConstants.columnOpId} = ?',
      whereArgs: [clientOpId],
      limit: 1,
    );
    if (ops.isEmpty) return false;
    final rowId = ops.first[DbConstants.columnRowId] as int;
    await txn.update(
      table,
      {
        DbConstants.columnRemoteId: serverId,
        DbConstants.columnUpdatedAt: remoteAt,
      },
      where: '${DbConstants.columnId} = ?',
      whereArgs: [rowId],
    );
    await txn.delete(
      DbConstants.tableOutbox,
      where: '${DbConstants.columnOpId} = ?',
      whereArgs: [clientOpId],
    );
    return true;
  }

  /// Maps a remote row onto local columns (same names per Phase 0, minus
  /// `id`/`owner_id`/`updated_at`). Child FK uuids resolve to local parent
  /// ids via `remote_id` matching; returns null when a parent is unknown
  /// (orphan — skipped; parents are pulled before children in the same run,
  /// so absence means the parent is genuinely gone, mirroring cascade).
  Future<Map<String, dynamic>?> _toLocalValues(
    Transaction txn,
    String table,
    Set<String> localColumns,
    Map<String, dynamic> remote,
  ) async {
    final out = <String, dynamic>{};
    final fks = fkParents[table] ?? const {};
    for (final entry in remote.entries) {
      final key = entry.key;
      if (key == 'id' || key == 'owner_id' || key == 'updated_at') continue;
      if (key == 'is_deleted') continue; // handled by caller
      if (!localColumns.contains(key)) continue; // ignore unknown columns
      if (fks.containsKey(key)) {
        final parentUuid = entry.value as String?;
        if (parentUuid == null) return null;
        final parentRows = await txn.query(
          fks[key]!,
          columns: [DbConstants.columnId],
          where: '${DbConstants.columnRemoteId} = ?',
          whereArgs: [parentUuid],
          limit: 1,
        );
        if (parentRows.isEmpty) return null;
        out[key] = parentRows.first[DbConstants.columnId] as int;
        continue;
      }
      out[key] = entry.value;
    }
    return out;
  }

  Future<Set<String>> _localColumns(String table) async {
    final info = await _db.rawQuery('PRAGMA table_info($table)');
    return {for (final col in info) col['name'] as String};
  }

  Future<int?> _lastPullAt(String table) async {
    final rows = await _db.query(
      DbConstants.tableSyncState,
      columns: [DbConstants.columnLastPullAt],
      where: '${DbConstants.columnTableName} = ?',
      whereArgs: [table],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first[DbConstants.columnLastPullAt] as int?;
  }

  Future<String?> _parkedError() async {
    final rows = await _db.query(
      DbConstants.tableOutbox,
      columns: [DbConstants.columnLastError],
      where:
          '${DbConstants.columnAttempts} >= ? '
          'AND ${DbConstants.columnLastError} IS NOT NULL',
      whereArgs: [maxAttempts],
      orderBy: '${DbConstants.columnCreatedAt} ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final count = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbConstants.tableOutbox} '
      'WHERE ${DbConstants.columnAttempts} >= ?',
      [maxAttempts],
    );
    final n = (count.first['c'] as int?) ?? 1;
    final first = rows.first[DbConstants.columnLastError] as String?;
    return n == 1
        ? '1 operation needs attention: $first'
        : '$n operations need attention (latest: $first)';
  }
}

enum _OpOutcome { acked, deferred, failed }

/// Result of pushing one table: acked-op count plus whether any op failed
/// (recorded per-op with attempts/last_error; the pull runs regardless).
typedef _PushOutcome = ({int acked, bool hadFailure});

/// Normalizes a server/fake `updated_at` (millis int or ISO-8601 string).
int asMillis(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) {
    final asInt = int.tryParse(value);
    if (asInt != null) return asInt;
    return DateTime.parse(value).millisecondsSinceEpoch;
  }
  throw ArgumentError('Unsupported updated_at value: $value');
}

/// Normalizes a server/fake `is_deleted` (0/1 int or bool).
bool asBool(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) return value == '1' || value.toLowerCase() == 'true';
  return false;
}

/// Visible for tests: decode an outbox payload.
Map<String, dynamic> decodePayload(String raw) =>
    jsonDecode(raw) as Map<String, dynamic>;
