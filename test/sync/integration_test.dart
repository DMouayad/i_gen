import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/sync/sync_repo.dart';
import 'package:i_gen/sync/sync_models.dart';

import '../helpers/test_db.dart';

void main() {
  late Database dbDeviceA;
  late Database dbDeviceB;
  late SyncRepository syncRepoA;
  late SyncRepository syncRepoB;

  const deviceAId = 'device-a-id';
  const deviceAName = 'Device A';
  const deviceBId = 'device-b-id';
  const deviceBName = 'Device B';

  setUpAll(() {
    initTestDatabase();
  });

  setUp(() async {
    dbDeviceA = await createTestDatabase();
    dbDeviceB = await createTestDatabase();
    syncRepoA = SyncRepository(dbDeviceA);
    syncRepoB = SyncRepository(dbDeviceB);
  });

  tearDown(() async {
    // Clean up databases after each test
    await deleteTestDatabase(dbDeviceA);
    await deleteTestDatabase(dbDeviceB);
  });

  // test/sync/sync_integration_test.dart

  /// Helper to sync from A to B
  Future<SyncResult> syncAtoB({int? anchorOverride}) async {
    final anchor =
        anchorOverride ?? await syncRepoB.getLastSyncAnchor(deviceAId);
    print('[TEST] Syncing A->B with anchor: $anchor');

    final payload = await syncRepoA.getChangesSince(
      anchor,
      deviceAId,
      deviceAName,
    );
    print(
      '[TEST] Payload: ${payload.products.length} products, ${payload.invoices.length} invoices',
    );

    final result = await syncRepoB.mergePayload(payload);
    print(
      '[TEST] Result: inserted=${result.inserted}, updated=${result.updated}, skipped=${result.skipped}',
    );

    // Show updated anchor
    final newAnchor = await syncRepoB.getLastSyncAnchor(deviceAId);
    print('[TEST] New anchor for A: $newAnchor');

    return result;
  }

  /// Helper to sync from B to A
  Future<SyncResult> syncBtoA({int? anchorOverride}) async {
    final anchor =
        anchorOverride ?? await syncRepoA.getLastSyncAnchor(deviceBId);
    print('[TEST] Syncing B->A with anchor: $anchor');

    final payload = await syncRepoB.getChangesSince(
      anchor,
      deviceBId,
      deviceBName,
    );
    print(
      '[TEST] Payload: ${payload.products.length} products, ${payload.invoices.length} invoices',
    );

    final result = await syncRepoA.mergePayload(payload);
    print(
      '[TEST] Result: inserted=${result.inserted}, updated=${result.updated}, skipped=${result.skipped}',
    );

    // Show updated anchor
    final newAnchor = await syncRepoA.getLastSyncAnchor(deviceBId);
    print('[TEST] New anchor for B: $newAnchor');

    return result;
  }

  /// Helper to insert a product
  Future<int> insertProduct(
    Database db,
    String model,
    String name,
    String uuid,
    int timestamp,
  ) async {
    return await db.insert(DbConstants.tableProduct, {
      DbConstants.columnProductModel: model,
      DbConstants.columnProductName: name,
      DbConstants.columnUuid: uuid,
      DbConstants.columnUpdatedAt: timestamp,
    });
  }

  /// Helper to insert a price category
  Future<int> insertCategory(
    Database db,
    String name,
    String currency,
    String uuid,
    int timestamp,
  ) async {
    return await db.insert(DbConstants.tablePriceCategory, {
      DbConstants.columnPriceCategoryName: name,
      DbConstants.columnPriceCategoryCurrency: currency,
      DbConstants.columnUuid: uuid,
      DbConstants.columnUpdatedAt: timestamp,
    });
  }

  /// Helper to insert a price
  Future<int> insertPrice(
    Database db,
    int productId,
    int categoryId,
    double price,
    String uuid,
    int timestamp,
  ) async {
    return await db.insert(DbConstants.tablePrices, {
      DbConstants.columnPricesProductId: productId,
      DbConstants.columnPricesPriceCategoryId: categoryId,
      DbConstants.columnPricesPrice: price,
      DbConstants.columnUuid: uuid,
      DbConstants.columnUpdatedAt: timestamp,
    });
  }

  /// Helper to insert an invoice
  Future<int> insertInvoice(
    Database db,
    String customer,
    double total,
    String uuid,
    int timestamp,
  ) async {
    return await db.insert(DbConstants.tableInvoice, {
      DbConstants.columnCustomerName: customer,
      DbConstants.columnInvoiceDate: DateTime.now().toIso8601String(),
      DbConstants.columnInvoiceTotal: total,
      DbConstants.columnInvoiceCurrency: 'USD',
      DbConstants.columnInvoiceDiscount: 0,
      DbConstants.columnUuid: uuid,
      DbConstants.columnUpdatedAt: timestamp,
    });
  }

  /// Helper to insert an invoice line
  Future<int> insertInvoiceLine(
    Database db,
    int invoiceId,
    int productId,
    int amount,
    double price,
    String uuid,
    int timestamp,
  ) async {
    return await db.insert(DbConstants.tableInvoiceLine, {
      DbConstants.columnInvoiceLineInvoiceId: invoiceId,
      DbConstants.columnInvoiceLineProductId: productId,
      DbConstants.columnInvoiceLineAmount: amount,
      DbConstants.columnInvoiceLinePrice: price,
      DbConstants.columnUuid: uuid,
      DbConstants.columnUpdatedAt: timestamp,
    });
  }

  // ============================================================
  // SCENARIO 1: Basic Bidirectional Sync
  // ============================================================

  group('Scenario: Basic Bidirectional Sync', () {
    test('Device A creates product, syncs to B, B sees it', () async {
      // Device A creates a product
      await insertProduct(dbDeviceA, 'PROD-001', 'Product 1', 'uuid-001', 1000);

      // Sync A -> B
      final result = await syncAtoB(anchorOverride: 0);

      expect(result.inserted, 1);

      // Verify B has the product
      final productsB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productsB, hasLength(1));
      expect(productsB.first['model'], 'PROD-001');
      expect(productsB.first['uuid'], 'uuid-001');
    });

    test(
      'Both devices create products, bidirectional sync merges all',
      () async {
        // Device A creates products
        await insertProduct(
          dbDeviceA,
          'PROD-A1',
          'Product A1',
          'uuid-a1',
          1000,
        );
        await insertProduct(
          dbDeviceA,
          'PROD-A2',
          'Product A2',
          'uuid-a2',
          1001,
        );

        // Device B creates products
        await insertProduct(
          dbDeviceB,
          'PROD-B1',
          'Product B1',
          'uuid-b1',
          1002,
        );
        await insertProduct(
          dbDeviceB,
          'PROD-B2',
          'Product B2',
          'uuid-b2',
          1003,
        );

        // Sync A -> B
        final resultAB = await syncAtoB(anchorOverride: 0);
        expect(resultAB.inserted, 2);

        // Sync B -> A
        final resultBA = await syncBtoA(anchorOverride: 0);
        expect(resultBA.inserted, 2);

        // Both should have 4 products
        final productsA = await dbDeviceA.query(DbConstants.tableProduct);
        final productsB = await dbDeviceB.query(DbConstants.tableProduct);

        expect(productsA, hasLength(4));
        expect(productsB, hasLength(4));
      },
    );

    test('Sync only transfers changes since last sync', () async {
      // Device A creates first product
      await insertProduct(dbDeviceA, 'PROD-001', 'Product 1', 'uuid-001', 1000);

      // First sync
      await syncAtoB(anchorOverride: 0);

      // Device A creates second product (later)
      await insertProduct(dbDeviceA, 'PROD-002', 'Product 2', 'uuid-002', 2000);

      // Second sync - should only get the new product
      final result = await syncAtoB();
      expect(result.inserted, 1);
      expect(result.skipped, 0); // Should not re-process first product

      final productsB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productsB, hasLength(2));
    });
  });

  // ============================================================
  // SCENARIO 2: Conflict Resolution (Last Write Wins)
  // ============================================================

  group('Scenario: Conflict Resolution', () {
    test('Same product edited on both devices - newer wins', () async {
      // Both devices have the same product (simulating shared seed data)
      await insertProduct(
        dbDeviceA,
        'PROD-001',
        'Original Name',
        'uuid-001',
        1000,
      );
      await insertProduct(
        dbDeviceB,
        'PROD-001',
        'Original Name',
        'uuid-001',
        1000,
      );

      // Device A edits first (older timestamp)
      await dbDeviceA.update(
        DbConstants.tableProduct,
        {
          DbConstants.columnProductName: 'Name from A',
          DbConstants.columnUpdatedAt: 2000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );

      // Device B edits later (newer timestamp)
      await dbDeviceB.update(
        DbConstants.tableProduct,
        {
          DbConstants.columnProductName: 'Name from B',
          DbConstants.columnUpdatedAt: 3000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );

      // Sync A -> B (B should keep its version since it's newer)
      final resultAB = await syncAtoB(anchorOverride: 0);
      expect(resultAB.skipped, 1);

      final productB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productB.first['name'], 'Name from B');

      // Sync B -> A (A should get B's version)
      final resultBA = await syncBtoA(anchorOverride: 0);
      expect(resultBA.updated, 1);

      final productA = await dbDeviceA.query(DbConstants.tableProduct);
      expect(productA.first['name'], 'Name from B');
    });

    test('Price updated on both devices - newer wins', () async {
      // Setup: same product and category on both
      await insertProduct(
        dbDeviceA,
        'PROD-001',
        'Product 1',
        'prod-uuid',
        1000,
      );
      await insertProduct(
        dbDeviceB,
        'PROD-001',
        'Product 1',
        'prod-uuid',
        1000,
      );
      await insertCategory(dbDeviceA, 'Retail', 'USD', 'cat-uuid', 1000);
      await insertCategory(dbDeviceB, 'Retail', 'USD', 'cat-uuid', 1000);

      // Same price entry on both
      await insertPrice(dbDeviceA, 1, 1, 100.00, 'price-uuid', 1000);
      await insertPrice(dbDeviceB, 1, 1, 100.00, 'price-uuid', 1000);

      // Device A updates price
      await dbDeviceA.update(
        DbConstants.tablePrices,
        {
          DbConstants.columnPricesPrice: 120.00,
          DbConstants.columnUpdatedAt: 2000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['price-uuid'],
      );

      // Device B updates price later
      await dbDeviceB.update(
        DbConstants.tablePrices,
        {
          DbConstants.columnPricesPrice: 150.00,
          DbConstants.columnUpdatedAt: 3000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['price-uuid'],
      );

      // Bidirectional sync
      await syncAtoB(anchorOverride: 0);
      await syncBtoA(anchorOverride: 0);

      // Both should have B's price (150.00)
      final priceA = await dbDeviceA.query(DbConstants.tablePrices);
      final priceB = await dbDeviceB.query(DbConstants.tablePrices);

      expect(priceA.first['price'], 150.00);
      expect(priceB.first['price'], 150.00);
    });

    test(
      'Same model created on both devices with different UUIDs - newer wins',
      () async {
        // Device A creates product first
        await insertProduct(
          dbDeviceA,
          'PROD-001',
          'Name from A',
          'uuid-a',
          1000,
        );

        // Device B creates same model later
        await insertProduct(
          dbDeviceB,
          'PROD-001',
          'Name from B',
          'uuid-b',
          2000,
        );

        // Sync A -> B (B's version is newer, should keep it)
        final resultAB = await syncAtoB(anchorOverride: 0);
        expect(resultAB.skipped, 1);

        // Sync B -> A (A should get B's version)
        final resultBA = await syncBtoA(anchorOverride: 0);
        expect(resultBA.updated, 1);

        // Verify both have B's version
        final productA = await dbDeviceA.query(DbConstants.tableProduct);
        final productB = await dbDeviceB.query(DbConstants.tableProduct);

        expect(productA, hasLength(1));
        expect(productB, hasLength(1));
        expect(productA.first['name'], 'Name from B');
        expect(productA.first['uuid'], 'uuid-b');
      },
    );
  });

  // ============================================================
  // SCENARIO 3: Delete Synchronization
  // ============================================================

  group('Scenario: Delete Synchronization', () {
    test('Device A deletes product, sync removes it from B', () async {
      // Both devices have the product
      await insertProduct(dbDeviceA, 'PROD-001', 'Product 1', 'uuid-001', 1000);
      await insertProduct(dbDeviceB, 'PROD-001', 'Product 1', 'uuid-001', 1000);

      // Device A deletes the product
      await dbDeviceA.delete(
        DbConstants.tableProduct,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );
      await syncRepoA.recordDeletion(DbConstants.tableProduct, 'uuid-001');

      // Sync A -> B
      final result = await syncAtoB(anchorOverride: 0);
      expect(result.deleted, 1);

      // Verify B no longer has the product
      final productsB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productsB, isEmpty);
    });

    test(
      'Device A deletes, Device B modifies - delete wins (later timestamp)',
      () async {
        // Both devices have the product
        await insertProduct(
          dbDeviceA,
          'PROD-001',
          'Product 1',
          'uuid-001',
          1000,
        );
        await insertProduct(
          dbDeviceB,
          'PROD-001',
          'Product 1',
          'uuid-001',
          1000,
        );

        // Device B modifies
        await dbDeviceB.update(
          DbConstants.tableProduct,
          {
            DbConstants.columnProductName: 'Modified by B',
            DbConstants.columnUpdatedAt: 2000,
          },
          where: '${DbConstants.columnUuid} = ?',
          whereArgs: ['uuid-001'],
        );

        // Device A deletes later
        await dbDeviceA.delete(
          DbConstants.tableProduct,
          where: '${DbConstants.columnUuid} = ?',
          whereArgs: ['uuid-001'],
        );
        await dbDeviceA.insert(DbConstants.tableSyncTombstones, {
          'table_name': DbConstants.tableProduct,
          'uuid': 'uuid-001',
          'deleted_at': 3000, // Later than B's modification
        });

        // Sync A -> B (delete should win)
        final result = await syncAtoB(anchorOverride: 0);
        expect(result.deleted, 1);

        final productsB = await dbDeviceB.query(DbConstants.tableProduct);
        expect(productsB, isEmpty);
      },
    );

    test('Multiple deletes sync correctly', () async {
      // Both devices have 3 products
      for (int i = 1; i <= 3; i++) {
        await insertProduct(
          dbDeviceA,
          'PROD-00$i',
          'Product $i',
          'uuid-00$i',
          1000,
        );
        await insertProduct(
          dbDeviceB,
          'PROD-00$i',
          'Product $i',
          'uuid-00$i',
          1000,
        );
      }

      // Device A deletes product 1 and 3
      await dbDeviceA.delete(
        DbConstants.tableProduct,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );
      await dbDeviceA.delete(
        DbConstants.tableProduct,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-003'],
      );
      await syncRepoA.recordDeletion(DbConstants.tableProduct, 'uuid-001');
      await syncRepoA.recordDeletion(DbConstants.tableProduct, 'uuid-003');

      // Sync A -> B
      final result = await syncAtoB(anchorOverride: 0);
      expect(result.deleted, 2);

      // B should only have product 2
      final productsB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productsB, hasLength(1));
      expect(productsB.first['model'], 'PROD-002');
    });
  });

  // ============================================================
  // SCENARIO 4: Complex Invoice Sync
  // ============================================================

  group('Scenario: Invoice Sync', () {
    setUp(() async {
      // Setup products on both devices
      await insertProduct(
        dbDeviceA,
        'PROD-001',
        'Product 1',
        'prod-uuid-001',
        1000,
      );
      await insertProduct(
        dbDeviceA,
        'PROD-002',
        'Product 2',
        'prod-uuid-002',
        1000,
      );
      await insertProduct(
        dbDeviceB,
        'PROD-001',
        'Product 1',
        'prod-uuid-001',
        1000,
      );
      await insertProduct(
        dbDeviceB,
        'PROD-002',
        'Product 2',
        'prod-uuid-002',
        1000,
      );
    });

    test('Invoice with lines syncs correctly', () async {
      // Device A creates invoice with lines
      final invoiceId = await insertInvoice(
        dbDeviceA,
        'Customer A',
        299.97,
        'inv-uuid-001',
        2000,
      );
      await insertInvoiceLine(
        dbDeviceA,
        invoiceId,
        1,
        2,
        99.99,
        'line-uuid-001',
        2000,
      );
      await insertInvoiceLine(
        dbDeviceA,
        invoiceId,
        2,
        1,
        99.99,
        'line-uuid-002',
        2000,
      );

      // Sync A -> B
      final result = await syncAtoB(anchorOverride: 0);
      expect(result.inserted, greaterThanOrEqualTo(1));

      // Verify B has invoice and lines
      final invoicesB = await dbDeviceB.query(DbConstants.tableInvoice);
      final linesB = await dbDeviceB.query(DbConstants.tableInvoiceLine);

      expect(invoicesB, hasLength(1));
      expect(invoicesB.first['customer'], 'Customer A');
      expect(linesB, hasLength(2));
    });

    test('Invoice line updated syncs correctly', () async {
      // Both devices have the same invoice
      final invoiceIdA = await insertInvoice(
        dbDeviceA,
        'Customer',
        100.00,
        'inv-uuid',
        1000,
      );
      final invoiceIdB = await insertInvoice(
        dbDeviceB,
        'Customer',
        100.00,
        'inv-uuid',
        1000,
      );
      await insertInvoiceLine(
        dbDeviceA,
        invoiceIdA,
        1,
        1,
        100.00,
        'line-uuid',
        1000,
      );
      await insertInvoiceLine(
        dbDeviceB,
        invoiceIdB,
        1,
        1,
        100.00,
        'line-uuid',
        1000,
      );

      // Device A updates the line
      await dbDeviceA.update(
        DbConstants.tableInvoice,
        {
          DbConstants.columnInvoiceTotal: 200.00,
          DbConstants.columnUpdatedAt: 2000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['inv-uuid'],
      );
      await dbDeviceA.update(
        DbConstants.tableInvoiceLine,
        {
          DbConstants.columnInvoiceLineAmount: 2,
          DbConstants.columnUpdatedAt: 2000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['line-uuid'],
      );

      // Sync A -> B
      await syncAtoB(anchorOverride: 0);

      // Verify B has updated data
      final invoicesB = await dbDeviceB.query(DbConstants.tableInvoice);
      final linesB = await dbDeviceB.query(DbConstants.tableInvoiceLine);

      expect(invoicesB.first['total'], 200.00);
      expect(linesB.first['amount'], 2);
    });

    test(
      'Both devices create invoices for same customer - both sync',
      () async {
        // Device A creates invoice
        await insertInvoice(
          dbDeviceA,
          'Shared Customer',
          100.00,
          'inv-uuid-a',
          1000,
        );

        // Device B creates invoice
        await insertInvoice(
          dbDeviceB,
          'Shared Customer',
          200.00,
          'inv-uuid-b',
          2000,
        );

        // Bidirectional sync
        await syncAtoB(anchorOverride: 0);
        await syncBtoA(anchorOverride: 0);

        // Both should have 2 invoices
        final invoicesA = await dbDeviceA.query(DbConstants.tableInvoice);
        final invoicesB = await dbDeviceB.query(DbConstants.tableInvoice);

        expect(invoicesA, hasLength(2));
        expect(invoicesB, hasLength(2));
      },
    );
  });

  // ============================================================
  // SCENARIO 5: Seeded Data Sync
  // ============================================================

  group('Scenario: Seeded Data Sync', () {
    test(
      'Both devices have seeded products with same UUID - prices sync correctly',
      () async {
        // Simulate seeded products with deterministic UUIDs
        const seedUuid = 'seed-product-001';

        await insertProduct(
          dbDeviceA,
          'SEED-001',
          'Seeded Product',
          seedUuid,
          0,
        );
        await insertProduct(
          dbDeviceB,
          'SEED-001',
          'Seeded Product',
          seedUuid,
          0,
        );
        await insertCategory(dbDeviceA, 'Retail', 'USD', 'seed-cat-001', 0);
        await insertCategory(dbDeviceB, 'Retail', 'USD', 'seed-cat-001', 0);

        // Device A sets price
        await insertPrice(dbDeviceA, 1, 1, 50.00, 'price-001', 1000);

        // Sync A -> B
        final result = await syncAtoB(anchorOverride: 0);
        expect(result.inserted, 1);

        // Verify B has the price
        final pricesB = await dbDeviceB.query(DbConstants.tablePrices);
        expect(pricesB, hasLength(1));
        expect(pricesB.first['price'], 50.00);
      },
    );

    test('Prices for seeded products sync via model fallback', () async {
      // Simulate mismatched UUIDs (old migration issue)
      await insertProduct(dbDeviceA, 'SEED-001', 'Seeded Product', 'uuid-a', 0);
      await insertProduct(
        dbDeviceB,
        'SEED-001',
        'Seeded Product',
        'uuid-b',
        0,
      ); // Different UUID!
      await insertCategory(dbDeviceA, 'Retail', 'USD', 'cat-a', 0);
      await insertCategory(
        dbDeviceB,
        'Retail',
        'USD',
        'cat-b',
        0,
      ); // Different UUID!

      // Device A creates price
      await insertPrice(dbDeviceA, 1, 1, 75.00, 'price-001', 1000);

      // Export from A (includes product_model and category_name as fallback)
      final payload = await syncRepoA.getChangesSince(
        0,
        deviceAId,
        deviceAName,
      );

      // Manually add fallback fields (simulating updated export)
      final priceWithFallback = {
        ...payload.prices.first,
        'product_model': 'SEED-001',
        'category_name': 'Retail',
      };

      final modifiedPayload = SyncPayload(
        sourceDeviceId: payload.sourceDeviceId,
        sourceDeviceName: payload.sourceDeviceName,
        timestamp: payload.timestamp,
        products: payload.products,
        priceCategories: payload.priceCategories,
        prices: [priceWithFallback],
        invoices: payload.invoices,
        tombstones: payload.tombstones,
      );

      // Import to B
      final result = await syncRepoB.mergePayload(modifiedPayload);
      expect(result.inserted, greaterThanOrEqualTo(1));

      // Verify B has the price linked to correct local product
      final pricesB = await dbDeviceB.query(DbConstants.tablePrices);
      expect(pricesB, hasLength(1));
      expect(pricesB.first['product_id'], 1); // Local product ID
    });
  });

  // ============================================================
  // SCENARIO 6: Multiple Sync Rounds
  // ============================================================

  group('Scenario: Multiple Sync Rounds', () {
    test('Three rounds of changes sync correctly', () async {
      // Round 1: A creates product
      await insertProduct(dbDeviceA, 'PROD-001', 'V1', 'uuid-001', 1000);
      await syncAtoB(anchorOverride: 0);

      var productsB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productsB.first['name'], 'V1');

      // Round 2: A updates product
      await dbDeviceA.update(
        DbConstants.tableProduct,
        {
          DbConstants.columnProductName: 'V2',
          DbConstants.columnUpdatedAt: 2000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );
      await syncAtoB();

      productsB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productsB.first['name'], 'V2');

      // Round 3: A updates again
      await dbDeviceA.update(
        DbConstants.tableProduct,
        {
          DbConstants.columnProductName: 'V3',
          DbConstants.columnUpdatedAt: 3000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );
      await syncAtoB();

      productsB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productsB.first['name'], 'V3');
    });

    test('Alternating edits between devices sync correctly', () async {
      // Initial product
      await insertProduct(dbDeviceA, 'PROD-001', 'Initial', 'uuid-001', 1000);
      await syncAtoB(anchorOverride: 0);

      // B edits
      await dbDeviceB.update(
        DbConstants.tableProduct,
        {
          DbConstants.columnProductName: 'Edit by B',
          DbConstants.columnUpdatedAt: 2000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );
      await syncBtoA();

      var productA = await dbDeviceA.query(DbConstants.tableProduct);
      expect(productA.first['name'], 'Edit by B');

      // A edits
      await dbDeviceA.update(
        DbConstants.tableProduct,
        {
          DbConstants.columnProductName: 'Edit by A',
          DbConstants.columnUpdatedAt: 3000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );
      await syncAtoB();

      var productB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productB.first['name'], 'Edit by A');

      // B edits again
      await dbDeviceB.update(
        DbConstants.tableProduct,
        {
          DbConstants.columnProductName: 'Final Edit',
          DbConstants.columnUpdatedAt: 4000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );
      await syncBtoA();

      productA = await dbDeviceA.query(DbConstants.tableProduct);
      expect(productA.first['name'], 'Final Edit');
    });
  });

  // ============================================================
  // SCENARIO 7: Data Integrity
  // ============================================================

  group('Scenario: Data Integrity', () {
    test('All products exist on both devices after sync', () async {
      // Create 10 products on A
      for (int i = 1; i <= 10; i++) {
        await insertProduct(
          dbDeviceA,
          'PROD-$i',
          'Product $i',
          'uuid-$i',
          1000 + i,
        );
      }

      // Create 10 products on B (different models)
      for (int i = 11; i <= 20; i++) {
        await insertProduct(
          dbDeviceB,
          'PROD-$i',
          'Product $i',
          'uuid-$i',
          1000 + i,
        );
      }

      // Bidirectional sync
      await syncAtoB(anchorOverride: 0);
      await syncBtoA(anchorOverride: 0);

      // Both should have all 20 products
      final productsA = await dbDeviceA.query(DbConstants.tableProduct);
      final productsB = await dbDeviceB.query(DbConstants.tableProduct);

      expect(productsA, hasLength(20));
      expect(productsB, hasLength(20));

      // Verify all models exist
      final modelsA = productsA.map((p) => p['model']).toSet();
      final modelsB = productsB.map((p) => p['model']).toSet();

      for (int i = 1; i <= 20; i++) {
        expect(modelsA, contains('PROD-$i'));
        expect(modelsB, contains('PROD-$i'));
      }
    });

    test('No duplicate products after multiple syncs', () async {
      // Create product on A
      await insertProduct(dbDeviceA, 'PROD-001', 'Product 1', 'uuid-001', 1000);

      // Sync multiple times
      await syncAtoB(anchorOverride: 0);
      await syncAtoB(anchorOverride: 0);
      await syncAtoB(anchorOverride: 0);

      // Should still only have 1 product
      final productsB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productsB, hasLength(1));
    });

    test('UUIDs are preserved across sync', () async {
      const originalUuid = 'specific-uuid-12345';

      await insertProduct(
        dbDeviceA,
        'PROD-001',
        'Product 1',
        originalUuid,
        1000,
      );
      await syncAtoB(anchorOverride: 0);

      final productB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productB.first['uuid'], originalUuid);
    });

    test('Timestamps are preserved across sync', () async {
      const originalTimestamp = 1234567890;

      await insertProduct(
        dbDeviceA,
        'PROD-001',
        'Product 1',
        'uuid-001',
        originalTimestamp,
      );
      await syncAtoB(anchorOverride: 0);

      final productB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productB.first['updated_at'], originalTimestamp);
    });
  });

  // ============================================================
  // SCENARIO 8: Edge Cases
  // ============================================================

  group('Scenario: Edge Cases', () {
    test('Empty sync returns zero changes', () async {
      final result = await syncAtoB(anchorOverride: 0);

      expect(result.inserted, 0);
      expect(result.updated, 0);
      expect(result.deleted, 0);
      expect(result.skipped, 0);
    });

    test('Sync after no changes returns zero changes', () async {
      await insertProduct(dbDeviceA, 'PROD-001', 'Product 1', 'uuid-001', 1000);

      // First sync
      await syncAtoB(anchorOverride: 0);

      // Second sync with no changes
      final result = await syncAtoB();

      expect(result.inserted, 0);
      expect(result.updated, 0);
    });

    test('Very long product name syncs correctly', () async {
      final longName = 'A' * 1000;

      await insertProduct(dbDeviceA, 'PROD-001', longName, 'uuid-001', 1000);
      await syncAtoB(anchorOverride: 0);

      final productB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productB.first['name'], longName);
    });

    test('Unicode characters in product name sync correctly', () async {
      const unicodeName = 'المنتج العربي 中文产品 🎉';

      await insertProduct(dbDeviceA, 'PROD-001', unicodeName, 'uuid-001', 1000);
      await syncAtoB(anchorOverride: 0);

      final productB = await dbDeviceB.query(DbConstants.tableProduct);
      expect(productB.first['name'], unicodeName);
    });

    test('Zero price syncs correctly', () async {
      await insertProduct(
        dbDeviceA,
        'PROD-001',
        'Product 1',
        'prod-uuid',
        1000,
      );
      await insertProduct(
        dbDeviceB,
        'PROD-001',
        'Product 1',
        'prod-uuid',
        1000,
      );
      await insertCategory(dbDeviceA, 'Free', 'USD', 'cat-uuid', 1000);
      await insertCategory(dbDeviceB, 'Free', 'USD', 'cat-uuid', 1000);

      await insertPrice(dbDeviceA, 1, 1, 0.00, 'price-uuid', 1000);
      await syncAtoB(anchorOverride: 0);

      final priceB = await dbDeviceB.query(DbConstants.tablePrices);
      expect(priceB.first['price'], 0.00);
    });

    test('Negative discount syncs correctly', () async {
      // Some systems allow negative discounts (surcharges)
      await dbDeviceA.insert(DbConstants.tableInvoice, {
        DbConstants.columnCustomerName: 'Customer',
        DbConstants.columnInvoiceDate: DateTime.now().toIso8601String(),
        DbConstants.columnInvoiceTotal: 110.00,
        DbConstants.columnInvoiceCurrency: 'USD',
        DbConstants.columnInvoiceDiscount: -10.0, // Surcharge
        DbConstants.columnUuid: 'inv-uuid',
        DbConstants.columnUpdatedAt: 1000,
      });

      await syncAtoB(anchorOverride: 0);

      final invoiceB = await dbDeviceB.query(DbConstants.tableInvoice);
      expect(invoiceB.first['discount'], -10.0);
    });
  });

  // ============================================================
  // SCENARIO 9: Three Device Sync
  // ============================================================

  group('Scenario: Three Device Sync (A -> B -> C)', () {
    late Database dbDeviceC;
    late SyncRepository syncRepoC;

    setUp(() async {
      dbDeviceC = await createTestDatabase();
      syncRepoC = SyncRepository(dbDeviceC);
    });

    tearDown(() async {
      await deleteTestDatabase(dbDeviceC);
    });

    Future<SyncResult> syncBtoC({int? anchorOverride}) async {
      final anchor =
          anchorOverride ?? await syncRepoC.getLastSyncAnchor(deviceBId);
      print('[TEST] Syncing B->C with anchor: $anchor');

      final payload = await syncRepoB.getChangesSince(
        anchor,
        deviceBId,
        deviceBName,
      );
      print('[TEST] Payload: ${payload.products.length} products');

      final result = await syncRepoC.mergePayload(payload);
      print(
        '[TEST] Result: inserted=${result.inserted}, updated=${result.updated}, skipped=${result.skipped}',
      );

      return result;
    }

    test('Data flows A -> B -> C correctly', () async {
      // A creates product
      await insertProduct(dbDeviceA, 'PROD-001', 'From A', 'uuid-001', 1000);

      // Sync A -> B
      await syncAtoB(anchorOverride: 0);

      // Sync B -> C
      await syncBtoC();

      // C should have the product
      final productsC = await dbDeviceC.query(DbConstants.tableProduct);
      expect(productsC, hasLength(1));
      expect(productsC.first['name'], 'From A');
      expect(productsC.first['uuid'], 'uuid-001');
    });

    test('Edits propagate through chain', () async {
      // Setup: all have the product
      await insertProduct(dbDeviceA, 'PROD-001', 'V1', 'uuid-001', 1000);
      await syncAtoB(anchorOverride: 0);
      await syncBtoC();

      // A edits
      await dbDeviceA.update(
        DbConstants.tableProduct,
        {
          DbConstants.columnProductName: 'V2',
          DbConstants.columnUpdatedAt: 2000,
        },
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: ['uuid-001'],
      );

      // Propagate through chain
      await syncAtoB();
      await syncBtoC();

      // C should have the update
      final productC = await dbDeviceC.query(DbConstants.tableProduct);
      expect(productC.first['name'], 'V2');
    });
  });
}
