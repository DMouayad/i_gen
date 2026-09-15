import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:i_gen/sync/auth_info.dart';
import 'package:i_gen/sync/remote_gateway.dart';
import 'package:i_gen/sync/sync_service.dart';
import 'test_helper.dart';

/// In-memory fake remote gateway matching the contract of SupabaseGateway.
class RealWorldFakeGateway implements RemoteGateway {
  RealWorldFakeGateway({this.nowMillis = 10000});

  int nowMillis;
  int _seq = 0;

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

class TestDevice {
  TestDevice({required this.db, required this.remote, required this.auth})
    : products = ProductRepo(db),
      categories = PricingCategoryRepo(db),
      pricing = ProductPricingRepo(db),
      invoices = InvoiceRepo(db),
      sync = SyncService(
        db: db,
        remote: remote,
        auth: auth,
        backoffBase: Duration.zero,
      );

  final Database db;
  final RealWorldFakeGateway remote;
  final InMemoryAuthInfoProvider auth;
  final ProductRepo products;
  final PricingCategoryRepo categories;
  final ProductPricingRepo pricing;
  final InvoiceRepo invoices;
  final SyncService sync;

  static Future<TestDevice> create(
    RealWorldFakeGateway remote, {
    String? ownerId,
  }) async {
    final db = await openFreshTestDb();
    final auth = InMemoryAuthInfoProvider(ownerId);
    return TestDevice(db: db, remote: remote, auth: auth);
  }

  Future<void> dispose() async {
    await sync.dispose();
    await db.close();
  }
}

void main() {
  const owner = 'merchant-42';

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton(ProductsController(products: const []));
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  Future<void> updateController(List<Product> prods) async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton(ProductsController(products: prods));
  }

  test(
    '1. Week offline: 20+ mutations across 5 tables while logged out, login + sync drains cleanly',
    () async {
      final remote = RealWorldFakeGateway();
      final device = await TestDevice.create(
        remote,
        ownerId: null,
      ); // Logged out

      // Perform 20+ real repo actions across products, categories, pricing, invoices, invoice_lines
      final p1 = await device.products.insertProduct(
        model: 'P1',
        name: 'Widget',
      );
      final p2 = await device.products.insertProduct(
        model: 'P2',
        name: 'Gadget',
      );
      final p3 = await device.products.insertProduct(
        model: 'P3',
        name: 'Doohickey',
      );
      final p4 = await device.products.insertProduct(
        model: 'P4',
        name: 'Thingamajig',
      );
      await device.products.editProduct(p1.copyWith(name: 'Widget Pro'));
      await device.products.deleteProduct(p4);

      final catRetail = await device.categories.insert(
        PriceCategory(id: 0, name: 'Retail', currency: 'USD'),
      );
      final catWholesale = await device.categories.insert(
        PriceCategory(id: 0, name: 'Wholesale', currency: 'USD'),
      );
      final catVip = await device.categories.insert(
        PriceCategory(id: 0, name: 'VIP', currency: 'USD'),
      );
      await device.categories.save(name: 'Retail', currency: 'EUR');
      await device.categories.delete(catVip);

      await device.pricing.save(
        priceCategoryId: catRetail,
        productId: p1.id,
        price: 100,
        currency: 'EUR',
      );
      await device.pricing.save(
        priceCategoryId: catRetail,
        productId: p2.id,
        price: 200,
        currency: 'EUR',
      );
      await device.pricing.save(
        priceCategoryId: catWholesale,
        productId: p1.id,
        price: 80,
        currency: 'USD',
      );
      await device.pricing.save(
        priceCategoryId: catWholesale,
        productId: p2.id,
        price: 160,
        currency: 'USD',
      );
      await device.pricing.save(
        priceCategoryId: catRetail,
        productId: p1.id,
        price: 105,
        currency: 'EUR',
      ); // update

      await updateController([p1, p2, p3]);

      final inv1 = await device.invoices.insert(
        customerName: 'Customer A',
        currency: 'USD',
        date: DateTime(2026, 9, 1),
        total: 300,
        discount: 0,
        lines: [
          InvoiceTableRow(product: p1, amount: 1, unitPrice: 100),
          InvoiceTableRow(product: p2, amount: 1, unitPrice: 200),
        ],
      );
      final inv2 = await device.invoices.insert(
        customerName: 'Customer B',
        currency: 'USD',
        date: DateTime(2026, 9, 2),
        total: 100,
        discount: 10,
        lines: [InvoiceTableRow(product: p1, amount: 1, unitPrice: 100)],
      );
      await device.invoices.insert(
        customerName: 'Customer A',
        currency: 'USD',
        date: DateTime(2026, 9, 3),
        total: 200,
        discount: 0,
        invoiceId: inv1.id,
        lines: [InvoiceTableRow(product: p2, amount: 1, unitPrice: 200)],
      );
      await device.invoices.delete(inv2);

      final outboxCount = await tableCount(device.db, DbConstants.tableOutbox);
      expect(outboxCount, greaterThanOrEqualTo(20));

      // While logged out: syncNow skips, nothing sent to remote
      final skipped = await device.sync.syncNow();
      expect(skipped.skippedUnauthenticated, isTrue);
      expect(remote.deliveredOpIds, isEmpty);

      // Login and sync
      device.auth.setOwnerId(owner);
      final result = await device.sync.syncNow();
      expect(result.synced, isTrue);
      expect(await tableCount(device.db, DbConstants.tableOutbox), 0);

      // Verify remote_ids populated for all surviving local rows
      final liveProducts = await device.products.getProducts();
      expect(liveProducts, hasLength(3));
      for (final prod in liveProducts) {
        final row = (await device.db.query(
          DbConstants.tableProduct,
          where: '${DbConstants.columnId} = ?',
          whereArgs: [prod.id],
        )).first;
        expect(row[DbConstants.columnRemoteId], isNotNull);
      }

      final liveInvoices = await device.invoices.getInvoices();
      expect(liveInvoices, hasLength(1));
      final invRow = (await device.db.query(
        DbConstants.tableInvoice,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [liveInvoices.first.id],
      )).first;
      expect(invRow[DbConstants.columnRemoteId], isNotNull);

      await device.dispose();
    },
  );

  test(
    '2. Two devices diverge: edits on invoice + product delete, sync both converges to identical state via LWW',
    () async {
      final remote = RealWorldFakeGateway();
      final deviceA = await TestDevice.create(remote, ownerId: owner);
      final deviceB = await TestDevice.create(remote, ownerId: owner);

      // Initial setup on device A: 2 products and 1 invoice
      final pA1 = await deviceA.products.insertProduct(
        model: 'DA1',
        name: 'Alpha',
      );
      final pA2 = await deviceA.products.insertProduct(
        model: 'DA2',
        name: 'Beta',
      );
      await updateController([pA1, pA2]);
      final invA = await deviceA.invoices.insert(
        customerName: 'Shared Client',
        currency: 'USD',
        date: DateTime(2026, 9, 1),
        total: 50,
        discount: 0,
        lines: [InvoiceTableRow(product: pA1, amount: 5, unitPrice: 10)],
      );

      // Sync A up, then pull on B
      await deviceA.sync.syncNow();
      await deviceB.sync.syncNow();

      final bProducts = await deviceB.products.getProducts();
      expect(bProducts, hasLength(2));
      final bP1 = bProducts.firstWhere((p) => p.model == 'DA1');
      final bP2 = bProducts.firstWhere((p) => p.model == 'DA2');
      await updateController(bProducts);

      final bInvoices = await deviceB.invoices.getInvoices();
      expect(bInvoices, hasLength(1));
      final invB = bInvoices.first;

      // Divergence:
      // Device A edits product 1 name at t=now
      await deviceA.products.editProduct(pA1.copyWith(name: 'Alpha A Version'));
      // Device B deletes product 1 at t=now+10ms
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await deviceB.products.deleteProduct(bP1);

      // Device A updates invoice date
      await deviceA.invoices.insert(
        customerName: 'Shared Client',
        currency: 'USD',
        date: DateTime(2026, 9, 10),
        total: 50,
        discount: 0,
        invoiceId: invA.id,
        lines: [InvoiceTableRow(product: pA1, amount: 5, unitPrice: 10)],
      );

      // Device B updates invoice total + customer at t=now+20ms (newer)
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await deviceB.invoices.insert(
        customerName: 'Client Modified By B',
        currency: 'USD',
        date: DateTime(2026, 9, 15),
        total: 70,
        discount: 0,
        invoiceId: invB.id,
        lines: [InvoiceTableRow(product: bP2, amount: 7, unitPrice: 10)],
      );

      // Sync A then B then A to settle convergence
      await deviceA.sync.syncNow();
      await deviceB.sync.syncNow();
      await deviceA.sync.syncNow();

      // Both devices should agree:
      // Product 1 was deleted newer -> hidden on both
      expect((await deviceA.products.getProducts()).map((p) => p.model), [
        'DA2',
      ]);
      expect((await deviceB.products.getProducts()).map((p) => p.model), [
        'DA2',
      ]);

      // Invoice was modified by B newer -> B's customer name wins on both
      final finalA = await deviceA.invoices.getInvoices();
      final finalB = await deviceB.invoices.getInvoices();
      expect(finalA.first.customerName, 'Client Modified By B');
      expect(finalB.first.customerName, 'Client Modified By B');
      expect(finalA.first.total, 70);
      expect(finalB.first.total, 70);

      await deviceA.dispose();
      await deviceB.dispose();
    },
  );

  test(
    '3. Edit war on one row with 3 alternating newer/older timestamps: newest wins and checkpoint advances',
    () async {
      final remote = RealWorldFakeGateway(nowMillis: 50000);
      final device = await TestDevice.create(remote, ownerId: owner);

      // Local product created with timestamp 1000
      final p = await device.products.insertProduct(
        model: 'WAR-1',
        name: 'Initial',
      );
      await device.sync.syncNow();
      final remoteId =
          (await device.db.query(
                DbConstants.tableProduct,
                where: '${DbConstants.columnId} = ?',
                whereArgs: [p.id],
              )).first[DbConstants.columnRemoteId]
              as String;

      // Remote receives three edits behind our back:
      // 1. updated_at: 60000 -> "Remote V1"
      // 2. updated_at: 55000 (stale clock / reordered) -> "Remote Stale"
      // 3. updated_at: 70000 -> "Remote Winner"
      remote.seed(
        'products',
        id: remoteId,
        ownerId: owner,
        updatedAt: 60000,
        fields: {'model': 'WAR-1', 'name': 'Remote V1'},
      );
      remote.seed(
        'products',
        id: remoteId,
        ownerId: owner,
        updatedAt: 55000,
        fields: {'model': 'WAR-1', 'name': 'Remote Stale'},
      );
      remote.seed(
        'products',
        id: remoteId,
        ownerId: owner,
        updatedAt: 70000,
        fields: {'model': 'WAR-1', 'name': 'Remote Winner'},
      );

      final result = await device.sync.syncNow();
      expect(result.synced, isTrue);

      // Newest remote wins
      final prods = await device.products.getProducts();
      expect(prods.first.name, 'Remote Winner');

      // Checkpoint advanced to 70000
      final state = await device.db.query(
        DbConstants.tableSyncState,
        where: '${DbConstants.columnTableName} = ?',
        whereArgs: [DbConstants.tableProduct],
      );
      expect(state.first[DbConstants.columnLastPullAt], 70000);

      await device.dispose();
    },
  );

  test(
    '4. Invoice rewrite suite via real InvoiceRepo: remove line, change product, add line, assert stable _ids and tombstones',
    () async {
      final remote = RealWorldFakeGateway();
      final device = await TestDevice.create(remote, ownerId: owner);

      final p1 = await device.products.insertProduct(
        model: 'P1',
        name: 'Item 1',
      );
      final p2 = await device.products.insertProduct(
        model: 'P2',
        name: 'Item 2',
      );
      final p3 = await device.products.insertProduct(
        model: 'P3',
        name: 'Item 3',
      );
      await updateController([p1, p2, p3]);

      // Create invoice with lines for p1 and p2
      final created = await device.invoices.insert(
        customerName: 'Rewrite Test Corp',
        currency: 'USD',
        date: DateTime(2026, 9, 1),
        total: 30,
        discount: 0,
        lines: [
          InvoiceTableRow(product: p1, amount: 1, unitPrice: 10),
          InvoiceTableRow(product: p2, amount: 2, unitPrice: 10),
        ],
      );
      await device.sync.syncNow();

      final line1Before = (await device.db.query(
        DbConstants.tableInvoiceLine,
        where:
            '${DbConstants.columnInvoiceLineInvoiceId} = ? AND ${DbConstants.columnInvoiceLineProductId} = ?',
        whereArgs: [created.id, p1.id],
      )).first;
      final line1Id = line1Before[DbConstants.columnId] as int;
      final line1RemoteId = line1Before[DbConstants.columnRemoteId] as String?;
      expect(line1RemoteId, isNotNull);

      // Rewrite: keep p1 (change amount), remove p2, add p3
      await device.invoices.insert(
        customerName: 'Rewrite Test Corp',
        currency: 'USD',
        date: DateTime(2026, 9, 2),
        total: 50,
        discount: 0,
        invoiceId: created.id,
        lines: [
          InvoiceTableRow(product: p1, amount: 3, unitPrice: 10),
          InvoiceTableRow(product: p3, amount: 2, unitPrice: 10),
        ],
      );

      // Check local lines before sync:
      // p1 updated in place (same _id)
      final line1After = (await device.db.query(
        DbConstants.tableInvoiceLine,
        where:
            '${DbConstants.columnInvoiceLineInvoiceId} = ? AND ${DbConstants.columnInvoiceLineProductId} = ?',
        whereArgs: [created.id, p1.id],
      )).first;
      expect(line1After[DbConstants.columnId], line1Id);

      // p2 line is soft-deleted
      final line2After = (await device.db.query(
        DbConstants.tableInvoiceLine,
        where:
            '${DbConstants.columnInvoiceLineInvoiceId} = ? AND ${DbConstants.columnInvoiceLineProductId} = ?',
        whereArgs: [created.id, p2.id],
      )).first;
      expect(line2After[DbConstants.columnIsDeleted], 1);

      // Sync to remote
      await device.sync.syncNow();

      // Verify server has 1 tombstone for removed line, updated p1 line, and new p3 line
      final remoteLines = remote.table('invoice_lines').values.toList();
      expect(remoteLines, hasLength(3));
      final p2Remote = remoteLines.firstWhere((l) => l['is_deleted'] == 1);
      expect(p2Remote['is_deleted'], 1);

      await device.dispose();
    },
  );

  test(
    '5. Restart recovery: enqueue ops, close + reopen db via real DbProvider, sync drains without duplicates',
    () async {
      final remote = RealWorldFakeGateway();
      final tempDb = await openFreshTestDb();
      final path = tempDb.path;

      final repo = ProductRepo(tempDb);
      await repo.insertProduct(model: 'REST-1', name: 'Restart Test');
      await repo.insertProduct(model: 'REST-2', name: 'To Delete');
      await repo.deleteProduct((await repo.getProducts()).last);

      expect(await tableCount(tempDb, DbConstants.tableOutbox), 3);
      await tempDb.close();

      // Reopen the same database path via real DbProvider
      final reopenedDb = await DbProvider.open(path);
      final auth = InMemoryAuthInfoProvider(owner);
      final sync = SyncService(
        db: reopenedDb,
        remote: remote,
        auth: auth,
        backoffBase: Duration.zero,
      );

      final result = await sync.syncNow();
      expect(result.synced, isTrue);
      expect(await tableCount(reopenedDb, DbConstants.tableOutbox), 0);

      final prods = await ProductRepo(reopenedDb).getProducts();
      expect(prods, hasLength(1));
      expect(prods.first.model, 'REST-1');

      await sync.dispose();
      await reopenedDb.close();
    },
  );

  test(
    '6. Tombstone propagation device-to-device: delete on A -> sync A -> sync B removes row on B and clears outbox',
    () async {
      final remote = RealWorldFakeGateway();
      final deviceA = await TestDevice.create(remote, ownerId: owner);
      final deviceB = await TestDevice.create(remote, ownerId: owner);

      final p = await deviceA.products.insertProduct(
        model: 'TOMB-1',
        name: 'Doomed Widget',
      );
      await deviceA.sync.syncNow();
      await deviceB.sync.syncNow();

      expect(
        (await deviceB.products.getProducts()).map((x) => x.model),
        contains('TOMB-1'),
      );

      // Device A deletes the product and syncs tombstone to server
      await deviceA.products.deleteProduct(p);
      await deviceA.sync.syncNow();

      // Verify remote has is_deleted: 1
      final remoteRows = remote
          .table('products')
          .values
          .where((r) => r['model'] == 'TOMB-1')
          .toList();
      expect(remoteRows.first['is_deleted'], 1);

      // Device B syncs: pulls tombstone, hard deletes locally, outbox clean
      await deviceB.sync.syncNow();
      expect((await deviceB.products.getProducts()), isEmpty);
      expect(await tableCount(deviceB.db, DbConstants.tableOutbox), 0);

      await deviceA.dispose();
      await deviceB.dispose();
    },
  );

  test(
    '7. Logged-out sync attempt leaves remote untouched; login mid-queue then sync drains',
    () async {
      final remote = RealWorldFakeGateway();
      final device = await TestDevice.create(
        remote,
        ownerId: null,
      ); // logged out

      await device.products.insertProduct(model: 'AUTH-1', name: 'Auth Test');
      await device.products.insertProduct(model: 'AUTH-2', name: 'Auth Test 2');

      // Attempt sync while logged out
      final res1 = await device.sync.syncNow();
      expect(res1.skippedUnauthenticated, isTrue);
      expect(remote.deliveredOpIds, isEmpty);
      expect(remote.table('products'), isEmpty);

      // User logs in
      device.auth.setOwnerId(owner);

      // Enqueue one more item
      await device.products.insertProduct(model: 'AUTH-3', name: 'Auth Test 3');

      // Sync now drains all 3 items
      final res2 = await device.sync.syncNow();
      expect(res2.synced, isTrue);
      expect(await tableCount(device.db, DbConstants.tableOutbox), 0);
      expect(remote.table('products'), hasLength(3));

      await device.dispose();
    },
  );
}
