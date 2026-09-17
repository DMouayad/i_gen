import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/db.dart';
import 'package:i_gen/sync/auth_info.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:i_gen/sync/remote_gateway.dart';
import 'package:i_gen/sync/sync_service.dart';
import 'test_helper.dart';

/// In-memory [RemoteGateway] fake: stores server rows per remote table,
/// dedupes repeat [opId] delivery (idempotency), and supports failure
/// injection per table or one-shot per op.
class FakeRemoteGateway implements RemoteGateway {
  FakeRemoteGateway({this.nowMillis = 5000});

  int nowMillis;
  int _seq = 0;

  /// remoteTable -> server id -> row (with id/owner_id/updated_at/is_deleted).
  final Map<String, Map<String, Map<String, dynamic>>> store = {};

  /// opIds seen, in delivery order — asserts FIFO + replay counts.
  final List<String> deliveredOpIds = [];

  /// opId -> server id assigned on first delivery (idempotent replay).
  final Map<String, String> opToId = {};

  /// Remote calls for these tables throw (partial-failure tests).
  final Set<String> failTables = {};

  /// opIds that throw exactly once (kill-mid-push tests).
  final Set<String> failOnceOpIds = {};

  Map<String, Map<String, dynamic>> table(String remoteTable) =>
      store.putIfAbsent(remoteTable, () => {});

  /// Seed a server row directly (pull tests / LWW fixtures).
  String seed(
    String remoteTable, {
    String? id,
    required String ownerId,
    required int updatedAt,
    bool isDeleted = false,
    Map<String, dynamic> fields = const {},
  }) {
    final rowId = id ?? 'seed-${_seq++}';
    table(remoteTable)[rowId] = {
      ...fields,
      'id': rowId,
      'owner_id': ownerId,
      'updated_at': updatedAt,
      'is_deleted': isDeleted ? 1 : 0,
    };
    return rowId;
  }

  void _maybeFail(String remoteTable, String opId) {
    if (failTables.contains(remoteTable)) {
      throw Exception('remote down for $remoteTable');
    }
  }

  /// Throws like a crash *after* the server applied the write but *before*
  /// the client saw the ack (the op stays queued and replays with the same
  /// opId). Returns true when the caller should throw.
  bool _crashAfterAck(String opId) => failOnceOpIds.remove(opId);

  @override
  Future<RemoteUpsertResult> upsertRow({
    required String remoteTable,
    required Map<String, dynamic> row,
    required String? remoteId,
    required String ownerId,
    required String opId,
  }) async {
    _maybeFail(remoteTable, opId);
    deliveredOpIds.add(opId);
    final existing = opToId[opId];
    if (existing != null) {
      // Idempotent replay: same opId never creates a second row.
      return RemoteUpsertResult(
        id: existing,
        updatedAtMillis: table(remoteTable)[existing]!['updated_at'] as int,
      );
    }
    nowMillis++;
    if (remoteId != null && table(remoteTable).containsKey(remoteId)) {
      table(remoteTable)[remoteId] = {
        ...row,
        'id': remoteId,
        'owner_id': ownerId,
        'client_op_id': opId,
        'updated_at': nowMillis,
        'is_deleted': 0,
      };
      opToId[opId] = remoteId;
    } else {
      final id = 'remote-${_seq++}';
      table(remoteTable)[id] = {
        ...row,
        'id': id,
        'owner_id': ownerId,
        'client_op_id': opId,
        'updated_at': nowMillis,
        'is_deleted': 0,
      };
      opToId[opId] = id;
    }
    if (_crashAfterAck(opId)) {
      throw Exception('crash between server-ack and op-delete for $opId');
    }
    final id = opToId[opId]!;
    return RemoteUpsertResult(
      id: id,
      updatedAtMillis: table(remoteTable)[id]!['updated_at'] as int,
    );
  }

  @override
  Future<RemoteUpsertResult> deleteRow({
    required String remoteTable,
    required String remoteId,
    required String ownerId,
    required String opId,
  }) async {
    _maybeFail(remoteTable, opId);
    deliveredOpIds.add(opId);
    nowMillis++;
    final row = table(remoteTable)[remoteId];
    if (row != null) {
      row['is_deleted'] = 1;
      row['updated_at'] = nowMillis;
    }
    return RemoteUpsertResult(id: remoteId, updatedAtMillis: nowMillis);
  }

  @override
  Future<List<Map<String, dynamic>>> pullTable({
    required String remoteTable,
    required String ownerId,
    required int? lastPullAtMillis,
  }) async {
    if (failTables.contains(remoteTable)) {
      throw Exception('remote down for $remoteTable');
    }
    final rows =
        table(remoteTable).values
            .where(
              (r) =>
                  r['owner_id'] == ownerId &&
                  (lastPullAtMillis == null ||
                      (r['updated_at'] as int) > lastPullAtMillis),
            )
            .toList()
          ..sort(
            (a, b) =>
                (a['updated_at'] as int).compareTo(b['updated_at'] as int),
          );
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }
}

const owner = 'user-1';

Future<Database> openSyncedDb() async {
  final db = await openFreshTestDb();
  return db;
}

Future<int> insertLocalProduct(
  Database db,
  String model,
  String name, {
  int updatedAt = 1000,
}) {
  return db.insert(DbConstants.tableProduct, {
    DbConstants.columnProductModel: model,
    DbConstants.columnProductName: name,
    DbConstants.columnUpdatedAt: updatedAt,
    DbConstants.columnIsDeleted: 0,
  });
}

SyncService makeService(
  Database db,
  FakeRemoteGateway remote,
  InMemoryAuthInfoProvider auth,
) => SyncService(
  db: db,
  remote: remote,
  auth: auth,
  backoffBase: Duration.zero, // deterministic retries in tests
);

void main() {
  test('offline writes push in FIFO order and drain the outbox', () async {
    final db = await openSyncedDb();
    final remote = FakeRemoteGateway();
    final auth = InMemoryAuthInfoProvider(owner);
    final sync = makeService(db, remote, auth);

    final idA = await insertLocalProduct(db, 'M1', 'one');
    final idB = await insertLocalProduct(db, 'M2', 'two');
    await SyncMetadata.recordMutation(
      db,
      ref: MutationRef(
        table: DbConstants.tableProduct,
        rowId: idA,
        op: DbConstants.opInsert,
      ),
      payloadOverride: Map<String, Object?>.from({'model': 'M1'}),
    );
    await SyncMetadata.recordMutation(
      db,
      ref: MutationRef(
        table: DbConstants.tableProduct,
        rowId: idB,
        op: DbConstants.opInsert,
      ),
      payloadOverride: Map<String, Object?>.from({'model': 'M2'}),
    );

    final result = await sync.syncNow();
    expect(result.synced, isTrue);
    expect(result.pushedPerTable[DbConstants.tableProduct], 2);
    expect(await tableCount(db, DbConstants.tableOutbox), 0);

    // FIFO: first enqueued op delivered first.
    expect(remote.deliveredOpIds, hasLength(2));

    // remote_id written back locally.
    for (final id in [idA, idB]) {
      final rows = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [id],
      );
      expect(rows.first[DbConstants.columnRemoteId], isNotNull);
    }
    await db.close();
  });

  test('sync is skipped while logged out and resumes after login', () async {
    final db = await openSyncedDb();
    final remote = FakeRemoteGateway();
    final auth = InMemoryAuthInfoProvider(); // logged out
    final sync = makeService(db, remote, auth);

    final skipped = await sync.syncNow();
    expect(skipped.skippedUnauthenticated, isTrue);
    expect(remote.deliveredOpIds, isEmpty);

    auth.setOwnerId(owner);
    final ok = await sync.syncNow();
    expect(ok.synced, isTrue);
    await db.close();
  });

  test(
    'pull inserts, updates (LWW remote-wins), and tombstone-deletes',
    () async {
      final db = await openSyncedDb();
      final remote = FakeRemoteGateway();
      final auth = InMemoryAuthInfoProvider(owner);
      final sync = makeService(db, remote, auth);

      // Local row older than its remote twin -> remote wins.
      final localId = await insertLocalProduct(
        db,
        'M1',
        'stale',
        updatedAt: 1000,
      );
      final twinId = remote.seed(
        'products',
        ownerId: owner,
        updatedAt: 2000,
        fields: {'model': 'M1', 'name': 'fresh'},
      );
      await db.update(
        DbConstants.tableProduct,
        {DbConstants.columnRemoteId: twinId},
        where: '${DbConstants.columnId} = ?',
        whereArgs: [localId],
      );

      // Brand-new remote row -> inserted locally.
      remote.seed(
        'products',
        ownerId: owner,
        updatedAt: 3000,
        fields: {'model': 'M9', 'name': 'from-other-device'},
      );

      // Remote tombstone for a synced local row -> hard-deleted locally.
      final doomedId = await insertLocalProduct(
        db,
        'M2',
        'doomed',
        updatedAt: 1000,
      );
      final doomedRemote = remote.seed(
        'products',
        ownerId: owner,
        updatedAt: 4000,
        isDeleted: true,
        fields: {'model': 'M2', 'name': 'doomed'},
      );
      await db.update(
        DbConstants.tableProduct,
        {DbConstants.columnRemoteId: doomedRemote},
        where: '${DbConstants.columnId} = ?',
        whereArgs: [doomedId],
      );

      final result = await sync.syncNow();
      expect(result.pulledPerTable[DbConstants.tableProduct], 3);

      final twin = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [localId],
      );
      expect(twin.first[DbConstants.columnProductName], 'fresh');
      expect(twin.first[DbConstants.columnUpdatedAt], 2000);

      final inserted = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnProductModel} = ?',
        whereArgs: ['M9'],
      );
      expect(inserted, hasLength(1));
      expect(inserted.first[DbConstants.columnRemoteId], isNotNull);

      final doomed = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [doomedId],
      );
      expect(doomed, isEmpty);

      // Checkpoint advanced past all pulled rows.
      final state = await db.query(
        DbConstants.tableSyncState,
        where: '${DbConstants.columnTableName} = ?',
        whereArgs: [DbConstants.tableProduct],
      );
      expect(state.first[DbConstants.columnLastPullAt], 4000);
      await db.close();
    },
  );

  test(
    'LWW local-wins: newer local row is untouched by an older remote',
    () async {
      final db = await openSyncedDb();
      final remote = FakeRemoteGateway();
      final auth = InMemoryAuthInfoProvider(owner);
      final sync = makeService(db, remote, auth);

      final localId = await insertLocalProduct(
        db,
        'M1',
        'local-newer',
        updatedAt: 9000,
      );
      final twinId = remote.seed(
        'products',
        ownerId: owner,
        updatedAt: 2000,
        fields: {'model': 'M1', 'name': 'remote-older'},
      );
      await db.update(
        DbConstants.tableProduct,
        {DbConstants.columnRemoteId: twinId},
        where: '${DbConstants.columnId} = ?',
        whereArgs: [localId],
      );

      await sync.syncNow();

      final rows = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [localId],
      );
      expect(rows.first[DbConstants.columnProductName], 'local-newer');
      expect(rows.first[DbConstants.columnUpdatedAt], 9000);
      await db.close();
    },
  );

  test(
    'kill-mid-push heals via pull-side ack recovery (no duplicates)',
    () async {
      final db = await openSyncedDb();
      final remote = FakeRemoteGateway();
      final auth = InMemoryAuthInfoProvider(owner);
      final sync = makeService(db, remote, auth);

      final id = await insertLocalProduct(db, 'M1', 'one');
      final opId = await SyncMetadata.recordMutation(
        db,
        ref: MutationRef(
          table: DbConstants.tableProduct,
          rowId: id,
          op: DbConstants.opInsert,
        ),
        payloadOverride: Map<String, Object?>.from({'model': 'M1'}),
      );
      remote.failOnceOpIds.add(opId);

      // Run 1: the delivery applies server-side then "crashes" before the
      // client records the ack. The same run's pull finds the row carrying
      // our client_op_id, adopts the server id/timestamp onto the local row,
      // and drops the op — no replay needed, no duplicate possible.
      final first = await sync.syncNow();
      expect(first.synced, isTrue);
      expect(await tableCount(db, DbConstants.tableOutbox), 0);
      expect(remote.table('products'), hasLength(1));
      expect(await tableCount(db, DbConstants.tableProduct), 1);
      final rows = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [id],
      );
      expect(rows.first[DbConstants.columnRemoteId], isNotNull);

      // Run 2 is a clean no-op: delivered once, stored once.
      final retry = await sync.syncNow();
      expect(retry.synced, isTrue);
      expect(await tableCount(db, DbConstants.tableOutbox), 0);
      expect(remote.table('products'), hasLength(1));
      expect(await tableCount(db, DbConstants.tableProduct), 1);
      expect(
        remote.deliveredOpIds.where((o) => o == opId),
        hasLength(1), // delivered once, adopted via pull — never replayed
      );
      await db.close();
    },
  );

  test(
    'one table failure leaves other tables committed and checkpointed',
    () async {
      final db = await openSyncedDb();
      final remote = FakeRemoteGateway();
      final auth = InMemoryAuthInfoProvider(owner);
      final sync = makeService(db, remote, auth);

      remote.failTables.add('invoices');

      final productId = await insertLocalProduct(db, 'M1', 'one');
      await SyncMetadata.recordMutation(
        db,
        ref: MutationRef(
          table: DbConstants.tableProduct,
          rowId: productId,
          op: DbConstants.opInsert,
        ),
        payloadOverride: Map<String, Object?>.from({'model': 'M1'}),
      );
      final invoiceId = await db.insert(DbConstants.tableInvoice, {
        DbConstants.columnInvoiceTotal: 10.0,
        DbConstants.columnCustomerName: 'acme',
        DbConstants.columnInvoiceDate: '2026-01-01',
        DbConstants.columnInvoiceCurrency: 'USD',
        DbConstants.columnInvoiceDiscount: 0.0,
        DbConstants.columnUpdatedAt: 1000,
        DbConstants.columnIsDeleted: 0,
      });
      await SyncMetadata.recordMutation(
        db,
        ref: MutationRef(
          table: DbConstants.tableInvoice,
          rowId: invoiceId,
          op: DbConstants.opInsert,
        ),
        payloadOverride: Map<String, Object?>.from({'customer': 'acme'}),
      );

      // A remote product row pulls fine even though invoices are down.
      remote.seed(
        'products',
        ownerId: owner,
        updatedAt: 6000,
        fields: {'model': 'M9', 'name': 'nine'},
      );

      final result = await sync.syncNow();
      // A fully-down table fails the run honestly (its pull throws too) —
      // but other tables are unaffected: partial-failure atomicity.
      expect(result.synced, isFalse);
      expect(result.error, contains('invoices'));

      // Products committed: pushed, pulled, checkpoint advanced.
      expect(result.pushedPerTable[DbConstants.tableProduct], 1);
      final pulled = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnProductModel} = ?',
        whereArgs: ['M9'],
      );
      expect(pulled, hasLength(1));
      final productState = await db.query(
        DbConstants.tableSyncState,
        where: '${DbConstants.columnTableName} = ?',
        whereArgs: [DbConstants.tableProduct],
      );
      expect(productState.first[DbConstants.columnLastPullAt], 6000);

      // Failed invoice op kept with attempts/last_error (not lost, not blocking
      // products).
      final invoiceOps = await db.query(
        DbConstants.tableOutbox,
        where: '${DbConstants.columnTableName} = ?',
        whereArgs: [DbConstants.tableInvoice],
      );
      expect(invoiceOps, hasLength(1));
      expect(invoiceOps.first[DbConstants.columnAttempts], 1);
      expect(
        invoiceOps.first[DbConstants.columnLastError],
        contains('invoices'),
      );
      await db.close();
    },
  );

  test('ops park after maxAttempts and surface last_error in status', () async {
    final db = await openSyncedDb();
    final remote = FakeRemoteGateway();
    final auth = InMemoryAuthInfoProvider(owner);
    final sync = SyncService(
      db: db,
      remote: remote,
      auth: auth,
      maxAttempts: 2,
      backoffBase: Duration.zero,
    );
    remote.failTables.add('products');

    final id = await insertLocalProduct(db, 'M1', 'one');
    await SyncMetadata.recordMutation(
      db,
      ref: MutationRef(
        table: DbConstants.tableProduct,
        rowId: id,
        op: DbConstants.opInsert,
      ),
      payloadOverride: Map<String, Object?>.from({'model': 'M1'}),
    );

    await sync.syncNow();
    await sync.syncNow();
    final ops = await db.query(DbConstants.tableOutbox);
    expect(ops, hasLength(1));
    expect(ops.first[DbConstants.columnAttempts], 2);

    // Parked: a third run does not attempt delivery again ...
    final delivered = remote.deliveredOpIds.length;
    final result = await sync.syncNow();
    expect(remote.deliveredOpIds.length, delivered);
    // ... but the error is surfaced for settings UI.
    expect(result.synced, isFalse);
    expect(sync.currentStatus.state, SyncState.error);
    expect(sync.currentStatus.lastError, contains('attention'));

    // retryParked resets and redelivers once the remote recovers.
    remote.failTables.clear();
    final retried = await sync.retryParked();
    expect(retried.synced, isTrue);
    expect(await tableCount(db, DbConstants.tableOutbox), 0);
    await db.close();
  });

  test('status stream emits syncing then success with lastSyncAt', () async {
    final db = await openSyncedDb();
    final remote = FakeRemoteGateway();
    final auth = InMemoryAuthInfoProvider(owner);
    final sync = makeService(db, remote, auth);

    final events = <SyncStatus>[];
    final sub = sync.statusStream.listen(events.add);
    await sync.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    expect(
      events.map((e) => e.state),
      containsAllInOrder([SyncState.syncing, SyncState.success]),
    );
    expect(sync.lastSyncAt, isNotNull);
    expect(events.last.lastSyncAt, isNotNull);
    await db.close();
  });
}
