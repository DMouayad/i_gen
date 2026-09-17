import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/db.dart';
import 'package:i_gen/db_seeder.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:i_gen/sync/auth_info.dart';
import 'package:i_gen/sync/remote_gateway.dart';
import 'package:i_gen/sync/sync_service.dart' hide SyncStatus;
import 'test_helper.dart';

/// Fake remote with two read-visibility modes plus RLS-denial injection,
/// so role/tenant scenarios run without a server:
/// - [companySharedPull]: ignore the owner filter (company-visible catalog).
/// - [deniedTables]: throw on pull like an RLS policy denial.
class ConvergenceFakeGateway implements RemoteGateway {
  ConvergenceFakeGateway({this.nowMillis = 20000});

  int nowMillis;
  int _seq = 0;
  // Mirrors the real gateway: reads are company-visible (RLS is the lock),
  // so the flag defaults on; owner-scoped checks are asserted explicitly
  // where tenant isolation is the point.
  bool companySharedPull = true;
  final Set<String> deniedTables = {};
  final Set<String> deniedPushTables = {};

  final Map<String, Map<String, Map<String, dynamic>>> store = {};
  final List<String> deliveredOpIds = [];
  final Map<String, String> opToId = {};

  Map<String, Map<String, dynamic>> table(String remoteTable) =>
      store.putIfAbsent(remoteTable, () => {});

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

  @override
  Future<RemoteUpsertResult> upsertRow({
    required String remoteTable,
    required Map<String, dynamic> row,
    required String? remoteId,
    required String ownerId,
    required String opId,
  }) async {
    if (deniedPushTables.contains(remoteTable)) {
      throw Exception('RLS denied $remoteTable insert for this role');
    }
    deliveredOpIds.add(opId);
    final existing = opToId[opId];
    if (existing != null) {
      return RemoteUpsertResult(
        id: existing,
        updatedAtMillis: table(remoteTable)[existing]!['updated_at'] as int,
      );
    }
    nowMillis += 10;
    if (remoteId != null && table(remoteTable).containsKey(remoteId)) {
      // Mirrors SupabaseGateway: identity columns are server-owned after
      // insert — updates never move client_op_id or owner_id.
      final keptOpId = table(remoteTable)[remoteId]!['client_op_id'];
      final keptOwner = table(remoteTable)[remoteId]!['owner_id'];
      table(remoteTable)[remoteId] = {
        ...row,
        'id': remoteId,
        'owner_id': keptOwner,
        'client_op_id': keptOpId,
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
    deliveredOpIds.add(opId);
    nowMillis += 10;
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
    if (deniedTables.contains(remoteTable)) {
      throw Exception('RLS denied $remoteTable for this role');
    }
    final rows =
        table(remoteTable).values
            .where(
              (r) =>
                  (companySharedPull || r['owner_id'] == ownerId) &&
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

SyncService makeSync(
  Database db,
  ConvergenceFakeGateway remote,
  InMemoryAuthInfoProvider auth,
) =>
    SyncService(db: db, remote: remote, auth: auth, backoffBase: Duration.zero);

Future<String?> localRemoteId(Database db, String model) async {
  final rows = await db.query(
    DbConstants.tableProduct,
    columns: [DbConstants.columnRemoteId],
    where: '${DbConstants.columnProductModel} = ?',
    whereArgs: [model],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return rows.first[DbConstants.columnRemoteId] as String?;
}

void main() {
  setUp(() {
    SyncTrigger.instance.resetForTests();
  });

  tearDown(() {
    SyncTrigger.instance.resetForTests();
  });

  test(
    'two seeded devices, same owner, converge to one server row per model',
    () async {
      final remote = ConvergenceFakeGateway();
      final dbA = await openFreshTestDb();
      final dbB = await openFreshTestDb();
      final auth = InMemoryAuthInfoProvider('admin-1');
      final syncA = makeSync(dbA, remote, auth);
      final syncB = makeSync(dbB, remote, auth);

      await DbSeeder.seedProducts(dbA);
      await DbSeeder.seedProducts(dbB);

      // Deterministic seed keys: same key for the same model on both devices.
      final opsA = await outboxRows(dbA);
      final opsB = await outboxRows(dbB);
      expect(
        opsA.map((o) => o[DbConstants.columnOpId]),
        contains('seed-product-A1'),
      );
      expect(
        opsA.map((o) => o[DbConstants.columnOpId]).toSet(),
        opsB.map((o) => o[DbConstants.columnOpId]).toSet(),
      );

      await syncA.syncNow();
      await syncB.syncNow();

      // One server row per model — no duplicate twins.
      expect(remote.table('products'), hasLength(25));
      // Both devices adopted the same server uuids.
      expect(await localRemoteId(dbA, 'A1'), await localRemoteId(dbB, 'A1'));
      expect(await localRemoteId(dbA, 'A1'), isNotNull);
      expect(await tableCount(dbA, DbConstants.tableOutbox), 0);
      expect(await tableCount(dbB, DbConstants.tableOutbox), 0);

      await syncA.dispose();
      await syncB.dispose();
      await dbA.close();
      await dbB.close();
    },
  );

  test(
    'prices created on device A resolve on device B after convergence',
    () async {
      final remote = ConvergenceFakeGateway();
      final dbA = await openFreshTestDb();
      final dbB = await openFreshTestDb();
      final auth = InMemoryAuthInfoProvider('admin-1');
      final syncA = makeSync(dbA, remote, auth);
      final syncB = makeSync(dbB, remote, auth);

      await DbSeeder.seedProducts(dbA);
      await DbSeeder.seedProducts(dbB);
      await syncA.syncNow();
      await syncB.syncNow();

      // Catalog work happens on A only.
      final catId = await PricingCategoryRepo(
        dbA,
      ).insert(PriceCategory(id: 0, name: 'Retail', currency: 'USD'));
      final prodsA = await ProductRepo(dbA).getProducts();
      final a1 = prodsA.firstWhere((p) => p.model == 'A1');
      await ProductPricingRepo(dbA).save(
        priceCategoryId: catId,
        productId: a1.id,
        price: 42.5,
        currency: 'USD',
      );
      final pushResult = await syncA.syncNow();
      expect(pushResult.synced, isTrue);

      final pullResult = await syncB.syncNow();
      expect(pullResult.synced, isTrue);
      expect(
        pullResult.pulledPerTable[DbConstants.tablePrices],
        greaterThan(0),
      );

      final matrix = await ProductPricingRepo(dbB).getProductsPricing();
      expect(matrix['A1']?['Retail']?.price, 42.5);

      // Nothing held for retry, nothing errored.
      final ui = SyncTrigger.instance.state.value;
      expect(ui.skippedByTable.entries.where((e) => e.value > 0), isEmpty);
      expect(ui.status, SyncStatus.synced);

      await syncA.dispose();
      await syncB.dispose();
      await dbA.close();
      await dbB.close();
    },
  );

  test(
    'legacy duplicate server twins heal on pull without aborting the table',
    () async {
      final remote = ConvergenceFakeGateway();
      const owner = 'admin-1';
      // Pre-diverged server: two product rows, one model.
      final uuidKeep = remote.seed(
        'products',
        id: 'uuid-a1-first',
        ownerId: owner,
        updatedAt: 3000,
        fields: {'model': 'A1', 'name': 'Twin One'},
      );
      remote.seed(
        'products',
        id: 'uuid-a1-second',
        ownerId: owner,
        updatedAt: 4000,
        fields: {'model': 'A1', 'name': 'Twin Two'},
      );
      final catId = remote.seed(
        'price_categories',
        id: 'uuid-cat',
        ownerId: owner,
        updatedAt: 3500,
        fields: {'name': 'Retail', 'currency': 'USD'},
      );
      remote.seed(
        'prices',
        ownerId: owner,
        updatedAt: 3600,
        fields: {'product_id': uuidKeep, 'category_id': catId, 'price': 42.5},
      );

      // Device holds an unpushed local seed (never synced, no queued op).
      final db = await openFreshTestDb();
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'A1',
        DbConstants.columnProductName: 'Local',
        DbConstants.columnUpdatedAt: 1000,
        DbConstants.columnIsDeleted: 0,
      });
      final sync = makeSync(db, remote, InMemoryAuthInfoProvider(owner));

      final result = await sync.syncNow();
      expect(result.synced, isTrue);
      expect(result.error, isNull);

      // One local row, converged onto the first-seen server uuid; the table
      // pull did not abort and the checkpoint advanced (second run is quiet).
      expect(await tableCount(db, DbConstants.tableProduct), 1);
      expect(await localRemoteId(db, 'A1'), uuidKeep);
      final twin = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnProductModel} = ?',
        whereArgs: ['A1'],
      );
      expect(twin.single[DbConstants.columnProductName], 'Twin Two');
      final matrix = await ProductPricingRepo(db).getProductsPricing();
      expect(matrix['A1']?['Retail']?.price, 42.5);

      final again = await sync.syncNow();
      expect(again.pulledPerTable[DbConstants.tableProduct] ?? 0, 0);

      await sync.dispose();
      await db.close();
    },
  );

  test(
    'pull conflict on every table merges in place and never throws',
    () async {
      final remote = ConvergenceFakeGateway();
      const owner = 'admin-1';
      final db = await openFreshTestDb();
      final sync = makeSync(db, remote, InMemoryAuthInfoProvider(owner));

      // Local rows that collide with pulled rows on natural UNIQUE keys.
      final localProdId = await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'M1',
        DbConstants.columnProductName: 'local',
        DbConstants.columnUpdatedAt: 1000,
        DbConstants.columnIsDeleted: 0,
      });
      final localCatId = await db.insert(DbConstants.tablePriceCategory, {
        DbConstants.columnPriceCategoryName: 'Retail',
        DbConstants.columnPriceCategoryCurrency: 'USD',
        DbConstants.columnUpdatedAt: 1000,
        DbConstants.columnIsDeleted: 0,
      });
      remote.seed(
        'products',
        id: 'uuid-m1',
        ownerId: owner,
        updatedAt: 2000,
        fields: {'model': 'M1', 'name': 'remote'},
      );
      remote.seed(
        'price_categories',
        id: 'uuid-retail',
        ownerId: owner,
        updatedAt: 2000,
        fields: {'name': 'Retail', 'currency': 'EUR'},
      );

      final result = await sync.syncNow();
      expect(result.synced, isTrue);
      expect(result.error, isNull);

      // Update-in-place: same _ids, remote won.
      final prod = await db.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnProductModel} = ?',
        whereArgs: ['M1'],
      );
      expect(prod, hasLength(1));
      expect(prod.first[DbConstants.columnId], localProdId);
      expect(prod.first[DbConstants.columnProductName], 'remote');
      expect(prod.first[DbConstants.columnRemoteId], 'uuid-m1');
      final cat = await db.query(
        DbConstants.tablePriceCategory,
        where: '${DbConstants.columnPriceCategoryName} = ?',
        whereArgs: ['Retail'],
      );
      expect(cat, hasLength(1));
      expect(cat.first[DbConstants.columnId], localCatId);
      expect(cat.first[DbConstants.columnPriceCategoryCurrency], 'EUR');

      await sync.dispose();
      await db.close();
    },
  );

  test(
    'roles: employee cannot push the catalog (RLS) but converges on pull',
    () async {
      // Admin pushes the catalog.
      final remote = ConvergenceFakeGateway()..companySharedPull = true;
      final dbAdmin = await openFreshTestDb();
      final syncAdmin = makeSync(
        dbAdmin,
        remote,
        InMemoryAuthInfoProvider('admin-1'),
      );
      await DbSeeder.seedProducts(dbAdmin);
      final catId = await PricingCategoryRepo(
        dbAdmin,
      ).insert(PriceCategory(id: 0, name: 'Retail', currency: 'USD'));
      final a1 = (await ProductRepo(
        dbAdmin,
      ).getProducts()).firstWhere((p) => p.model == 'A1');
      await ProductPricingRepo(dbAdmin).save(
        priceCategoryId: catId,
        productId: a1.id,
        price: 42.5,
        currency: 'USD',
      );
      await syncAdmin.syncNow();

      // Employee device, same bundled seeds. Catalog writes are admin-only,
      // so seed pushes are denied (like the real RLS admin_write policies)
      // and dropped as best-effort; reads are company-visible (like the real
      // company_read policies), so the device converges onto the admin uuids.
      remote.deniedPushTables.addAll({
        'products',
        'price_categories',
        'prices',
      });
      final dbEmp = await openFreshTestDb();
      await DbSeeder.seedProducts(dbEmp);
      final syncEmp = makeSync(
        dbEmp,
        remote,
        InMemoryAuthInfoProvider('employee-7'),
      );

      final res = await syncEmp.syncNow();
      expect(res.synced, isTrue);
      expect(res.error, isNull);
      // Denied seeds dropped, never parked; uuids adopted; prices resolved.
      expect(await tableCount(dbEmp, DbConstants.tableOutbox), 0);
      expect(
        await localRemoteId(dbEmp, 'A1'),
        await localRemoteId(dbAdmin, 'A1'),
      );
      expect(
        (await PricingCategoryRepo(dbEmp).getAll()).map((c) => c.name),
        contains('Retail'),
      );
      expect(
        (await ProductPricingRepo(
          dbEmp,
        ).getProductsPricing())['A1']?['Retail']?.price,
        42.5,
      );

      await syncAdmin.dispose();
      await syncEmp.dispose();
      await dbAdmin.close();
      await dbEmp.close();
    },
  );

  test('orphan price skips are counted and reported, not silent', () async {
    final remote = ConvergenceFakeGateway();
    const owner = 'admin-1';
    // Price references parents this device never saw.
    final catId = remote.seed(
      'price_categories',
      ownerId: owner,
      updatedAt: 2000,
      fields: {'name': 'Retail', 'currency': 'USD'},
    );
    remote.seed(
      'prices',
      ownerId: owner,
      updatedAt: 2100,
      fields: {'product_id': 'uuid-ghost', 'category_id': catId, 'price': 9.0},
    );

    final db = await openFreshTestDb();
    final sync = makeSync(db, remote, InMemoryAuthInfoProvider(owner));
    final result = await sync.syncNow();

    expect(result.synced, isTrue);
    final ui = SyncTrigger.instance.state.value;
    expect(ui.skippedByTable[DbConstants.tablePrices], 1);
    // Checkpoint held: still skipped on the next run (parents may arrive).
    await sync.syncNow();
    expect(
      SyncTrigger.instance.state.value.skippedByTable[DbConstants.tablePrices],
      1,
    );

    await sync.dispose();
    await db.close();
  });

  test('denied seed pushes drop while real ops stay queued', () async {
    final remote = ConvergenceFakeGateway()..deniedPushTables.add('products');
    final db = await openFreshTestDb();
    final sync = makeSync(db, remote, InMemoryAuthInfoProvider('employee-7'));

    await DbSeeder.seedProducts(db);
    // A real user edit alongside the seeds.
    final realId = await ProductRepo(
      db,
    ).insertProduct(model: 'ZZ', name: 'zed');

    await sync.syncNow();

    final ops = await outboxRows(db);
    // All 25 seed ops dropped; the real op stays queued with attempts=1.
    expect(
      ops.where(
        (o) => (o[DbConstants.columnOpId] as String).startsWith('seed-'),
      ),
      isEmpty,
    );
    expect(ops, hasLength(1));
    expect(ops.first[DbConstants.columnRowId], realId.id);
    expect(ops.first[DbConstants.columnAttempts], 1);
    expect((await sync.syncNow()).synced, isTrue);

    await sync.dispose();
    await db.close();
  });

  test(
    'older orphan is retried, never jumped over by the checkpoint',
    () async {
      final remote = ConvergenceFakeGateway();
      const owner = 'admin-1';
      // Orphan (t=100) is OLDER than the merged category (t=200).
      final catId = remote.seed(
        'price_categories',
        ownerId: owner,
        updatedAt: 200,
        fields: {'name': 'Retail', 'currency': 'USD'},
      );
      remote.seed(
        'prices',
        ownerId: owner,
        updatedAt: 100,
        fields: {
          'product_id': 'uuid-ghost',
          'category_id': catId,
          'price': 9.0,
        },
      );

      final db = await openFreshTestDb();
      final sync = makeSync(db, remote, InMemoryAuthInfoProvider(owner));

      await sync.syncNow();
      var ui = SyncTrigger.instance.state.value;
      expect(ui.skippedByTable[DbConstants.tablePrices], 1);

      // Second run: the prices checkpoint was held, so the orphan is
      // re-fetched and still held; the category table (no skips of its own)
      // advanced independently and stays put — no duplicates anywhere.
      await sync.syncNow();
      ui = SyncTrigger.instance.state.value;
      expect(ui.skippedByTable[DbConstants.tablePrices], 1);
      expect(await tableCount(db, DbConstants.tablePriceCategory), 1);

      // Once the missing parent arrives, the price merges and the checkpoint
      // advances past both rows: a third run is quiet.
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'G1',
        DbConstants.columnProductName: 'ghost',
        DbConstants.columnRemoteId: 'uuid-ghost',
        DbConstants.columnUpdatedAt: 50,
        DbConstants.columnIsDeleted: 0,
      });
      final third = await sync.syncNow();
      expect(third.pulledPerTable[DbConstants.tablePrices], 1);
      expect(
        SyncTrigger.instance.state.value.skippedByTable.entries.where(
          (e) => e.value > 0,
        ),
        isEmpty,
      );
      expect(
        (await ProductPricingRepo(
          db,
        ).getProductsPricing())['G1']?['Retail']?.price,
        9.0,
      );

      await sync.dispose();
      await db.close();
    },
  );

  test(
    'pull transport failure surfaces per-table error, other tables sync',
    () async {
      final remote = ConvergenceFakeGateway()
        ..deniedTables.add('products')
        ..deniedTables.add('prices');
      const owner = 'distributor-3';
      remote.seed(
        'price_categories',
        ownerId: owner,
        updatedAt: 2000,
        fields: {'name': 'Retail', 'currency': 'USD'},
      );

      final db = await openFreshTestDb();
      final sync = makeSync(db, remote, InMemoryAuthInfoProvider(owner));
      final result = await sync.syncNow();

      expect(result.synced, isFalse);
      expect(result.error, contains('product pull'));
      // Allowed tables still merged.
      expect(
        (await PricingCategoryRepo(db).getAll()).map((c) => c.name),
        contains('Retail'),
      );
      final ui = SyncTrigger.instance.state.value;
      expect(ui.status, SyncStatus.error);
      expect(ui.lastError, contains('product pull'));

      await sync.dispose();
      await db.close();
    },
  );
}
