import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/sync/sync_repo.dart';
import 'package:i_gen/sync/sync_models.dart';

import '../helpers/test_db.dart';

void main() {
  late Database db;
  late SyncRepository syncRepo;

  setUpAll(() {
    initTestDatabase();
  });

  setUp(() async {
    db = await createTestDatabase();
    syncRepo = SyncRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncRepository - Export', () {
    test('getChangesSince returns empty payload for new database', () async {
      final payload = await syncRepo.getChangesSince(
        0,
        'device-1',
        'Test Device',
      );

      expect(payload.products, isEmpty);
      expect(payload.invoices, isEmpty);
      expect(payload.priceCategories, isEmpty);
      expect(payload.prices, isEmpty);
      expect(payload.tombstones, isEmpty);
    });

    test('getChangesSince returns all data when anchor is 0', () async {
      await seedTestData(db);

      final payload = await syncRepo.getChangesSince(
        0,
        'device-1',
        'Test Device',
      );

      expect(payload.products, hasLength(2));
      expect(payload.priceCategories, hasLength(1));
      expect(payload.prices, hasLength(1));
      expect(payload.invoices, hasLength(1));
    });

    test('getChangesSince only returns data after anchor', () async {
      final oldTime = DateTime.now().toUtc().millisecondsSinceEpoch;

      // Insert old data
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'OLD-001',
        DbConstants.columnProductName: 'Old Product',
        DbConstants.columnUuid: 'old-uuid',
        DbConstants.columnUpdatedAt: oldTime - 10000,
      });

      // Insert new data
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'NEW-001',
        DbConstants.columnProductName: 'New Product',
        DbConstants.columnUuid: 'new-uuid',
        DbConstants.columnUpdatedAt: oldTime + 10000,
      });

      final payload = await syncRepo.getChangesSince(
        oldTime,
        'device-1',
        'Test Device',
      );

      expect(payload.products, hasLength(1));
      expect(payload.products.first['model'], 'NEW-001');
    });

    test('getChangesSince includes tombstones', () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;

      await syncRepo.recordDeletion('product', 'deleted-product-uuid');

      final payload = await syncRepo.getChangesSince(
        now - 1000,
        'device-1',
        'Test Device',
      );

      expect(payload.tombstones, hasLength(1));
      expect(payload.tombstones.first.uuid, 'deleted-product-uuid');
    });

    test('export includes invoice lines with invoices', () async {
      await seedTestData(db);

      final payload = await syncRepo.getChangesSince(
        0,
        'device-1',
        'Test Device',
      );

      expect(payload.invoices, hasLength(1));
      expect(payload.invoices.first['lines'], isNotEmpty);
    });

    test('export includes product and category refs in prices', () async {
      await seedTestData(db);

      final payload = await syncRepo.getChangesSince(
        0,
        'device-1',
        'Test Device',
      );

      expect(payload.prices, hasLength(1));
      expect(payload.prices.first['product_uuid'], isNotNull);
      expect(payload.prices.first['category_uuid'], isNotNull);
    });
  });

  group('SyncRepository - Import Products', () {
    test('mergePayload inserts new product', () async {
      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
        products: [
          {
            'uuid': 'new-product-uuid',
            'model': 'NEW-001',
            'name': 'New Product',
            'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.inserted, 1);
      expect(result.updated, 0);

      final products = await db.query(DbConstants.tableProduct);
      expect(products, hasLength(1));
      expect(products.first['model'], 'NEW-001');
    });

    test(
      'mergePayload updates existing product when remote is newer',
      () async {
        final oldTime = DateTime.now().toUtc().millisecondsSinceEpoch - 10000;
        final newTime = DateTime.now().toUtc().millisecondsSinceEpoch;

        // Insert existing product
        await db.insert(DbConstants.tableProduct, {
          DbConstants.columnProductModel: 'PROD-001',
          DbConstants.columnProductName: 'Old Name',
          DbConstants.columnUuid: 'product-uuid-001',
          DbConstants.columnUpdatedAt: oldTime,
        });

        final payload = SyncPayload(
          sourceDeviceId: 'remote-device',
          sourceDeviceName: 'Remote',
          timestamp: newTime,
          products: [
            {
              'uuid': 'product-uuid-001',
              'model': 'PROD-001',
              'name': 'New Name',
              'updated_at': newTime,
            },
          ],
        );

        final result = await syncRepo.mergePayload(payload);

        expect(result.updated, 1);
        expect(result.inserted, 0);

        final products = await db.query(DbConstants.tableProduct);
        expect(products.first['name'], 'New Name');
      },
    );

    test('mergePayload skips product when local is newer', () async {
      final oldTime = DateTime.now().toUtc().millisecondsSinceEpoch - 10000;
      final newTime = DateTime.now().toUtc().millisecondsSinceEpoch;

      // Insert existing product with newer timestamp
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'PROD-001',
        DbConstants.columnProductName: 'Local Name',
        DbConstants.columnUuid: 'product-uuid-001',
        DbConstants.columnUpdatedAt: newTime,
      });

      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: oldTime,
        products: [
          {
            'uuid': 'product-uuid-001',
            'model': 'PROD-001',
            'name': 'Remote Name',
            'updated_at': oldTime,
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.skipped, 1);
      expect(result.updated, 0);

      final products = await db.query(DbConstants.tableProduct);
      expect(products.first['name'], 'Local Name');
    });

    test('mergePayload handles conflict by model when UUIDs differ', () async {
      final oldTime = DateTime.now().toUtc().millisecondsSinceEpoch - 10000;
      final newTime = DateTime.now().toUtc().millisecondsSinceEpoch;

      // Insert existing product with different UUID
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'PROD-001',
        DbConstants.columnProductName: 'Local Name',
        DbConstants.columnUuid: 'local-uuid',
        DbConstants.columnUpdatedAt: oldTime,
      });

      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: newTime,
        products: [
          {
            'uuid': 'remote-uuid',
            'model': 'PROD-001',
            'name': 'Remote Name',
            'updated_at': newTime,
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.updated, 1);

      final products = await db.query(DbConstants.tableProduct);
      expect(products, hasLength(1));
      expect(products.first['name'], 'Remote Name');
      expect(products.first['uuid'], 'remote-uuid');
    });
  });

  group('SyncRepository - Import Prices', () {
    setUp(() async {
      // Seed products and categories for price tests
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'PROD-001',
        DbConstants.columnProductName: 'Product 1',
        DbConstants.columnUuid: 'product-uuid-001',
        DbConstants.columnUpdatedAt: 1000,
      });

      await db.insert(DbConstants.tablePriceCategory, {
        DbConstants.columnPriceCategoryName: 'Retail',
        DbConstants.columnPriceCategoryCurrency: 'USD',
        DbConstants.columnUuid: 'category-uuid-001',
        DbConstants.columnUpdatedAt: 1000,
      });
    });

    test('mergePayload inserts new price', () async {
      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
        prices: [
          {
            'uuid': 'price-uuid-001',
            'price': 99.99,
            'product_uuid': 'product-uuid-001',
            'product_model': 'PROD-001',
            'category_uuid': 'category-uuid-001',
            'category_name': 'Retail',
            'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.inserted, 1);

      final prices = await db.query(DbConstants.tablePrices);
      expect(prices, hasLength(1));
      expect(prices.first['price'], 99.99);
    });

    test('mergePayload updates price when remote is newer', () async {
      final oldTime = DateTime.now().toUtc().millisecondsSinceEpoch - 10000;
      final newTime = DateTime.now().toUtc().millisecondsSinceEpoch;

      // Insert existing price
      await db.insert(DbConstants.tablePrices, {
        DbConstants.columnPricesProductId: 1,
        DbConstants.columnPricesPriceCategoryId: 1,
        DbConstants.columnPricesPrice: 50.00,
        DbConstants.columnUuid: 'price-uuid-001',
        DbConstants.columnUpdatedAt: oldTime,
      });

      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: newTime,
        prices: [
          {
            'uuid': 'price-uuid-001',
            'price': 75.00,
            'product_uuid': 'product-uuid-001',
            'category_uuid': 'category-uuid-001',
            'updated_at': newTime,
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.updated, 1);

      final prices = await db.query(DbConstants.tablePrices);
      expect(prices.first['price'], 75.00);
    });

    test('mergePayload resolves price by model when UUID not found', () async {
      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
        prices: [
          {
            'uuid': 'price-uuid-002',
            'price': 150.00,
            'product_uuid': 'non-existent-uuid',
            'product_model': 'PROD-001', // Fallback
            'category_uuid': 'non-existent-uuid',
            'category_name': 'Retail', // Fallback
            'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.inserted, 1);

      final prices = await db.query(DbConstants.tablePrices);
      expect(prices, hasLength(1));
    });

    test('mergePayload skips price when product not found', () async {
      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
        prices: [
          {
            'uuid': 'price-uuid-003',
            'price': 200.00,
            'product_uuid': 'non-existent',
            'product_model': 'NON-EXISTENT',
            'category_uuid': 'category-uuid-001',
            'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.inserted, 0);
      expect(result.errors, isNotEmpty);
    });
  });

  group('SyncRepository - Tombstones', () {
    test('recordDeletion creates tombstone', () async {
      await syncRepo.recordDeletion('product', 'deleted-uuid');

      final tombstones = await db.query(DbConstants.tableSyncTombstones);
      expect(tombstones, hasLength(1));
      expect(tombstones.first['uuid'], 'deleted-uuid');
      expect(tombstones.first['table_name'], 'product');
    });

    test('mergePayload applies tombstones', () async {
      // Insert product to be deleted
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'TO-DELETE',
        DbConstants.columnProductName: 'Delete Me',
        DbConstants.columnUuid: 'delete-me-uuid',
        DbConstants.columnUpdatedAt: 1000,
      });

      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: DateTime.now().toUtc().millisecondsSinceEpoch,
        tombstones: [
          Tombstone(
            tableName: DbConstants.tableProduct,
            uuid: 'delete-me-uuid',
            deletedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.deleted, 1);

      final products = await db.query(DbConstants.tableProduct);
      expect(products, isEmpty);
    });
  });

  group('SyncRepository - Sync History', () {
    test('getLastSyncAnchor returns 0 for unknown device', () async {
      final anchor = await syncRepo.getLastSyncAnchor('unknown-device');
      expect(anchor, 0);
    });

    test('mergePayload updates sync history', () async {
      final payload = SyncPayload(
        sourceDeviceId: 'device-123',
        sourceDeviceName: 'Test Device',
        timestamp: 1700000000000,
        products: [],
      );

      await syncRepo.mergePayload(payload);

      final history = await db.query(DbConstants.tableSyncHistory);
      expect(history, hasLength(1));
      expect(history.first['device_id'], 'device-123');
    });

    test('getSyncHistory returns all devices', () async {
      await db.insert(DbConstants.tableSyncHistory, {
        'device_id': 'device-1',
        'device_name': 'Device 1',
        'last_sync_at': 1000,
      });

      await db.insert(DbConstants.tableSyncHistory, {
        'device_id': 'device-2',
        'device_name': 'Device 2',
        'last_sync_at': 2000,
      });

      final history = await syncRepo.getSyncHistory();

      expect(history, hasLength(2));
    });
  });

  group('SyncRepository - Invoices', () {
    setUp(() async {
      await db.insert(DbConstants.tableProduct, {
        DbConstants.columnProductModel: 'PROD-001',
        DbConstants.columnProductName: 'Product 1',
        DbConstants.columnUuid: 'product-uuid-001',
        DbConstants.columnUpdatedAt: 1000,
      });
    });

    test('mergePayload inserts new invoice with lines', () async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;

      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: now,
        invoices: [
          {
            'uuid': 'invoice-uuid-001',
            'customer': 'Test Customer',
            'date': DateTime.now().toIso8601String(),
            'total': 199.98,
            'currency': 'USD',
            'discount': 0.0,
            'updated_at': now,
            'lines': [
              {
                'uuid': 'line-uuid-001',
                'product_uuid': 'product-uuid-001',
                'amount': 2,
                'price': 99.99,
                'updated_at': now,
              },
            ],
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.inserted, greaterThanOrEqualTo(1));

      final invoices = await db.query(DbConstants.tableInvoice);
      expect(invoices, hasLength(1));

      final lines = await db.query(DbConstants.tableInvoiceLine);
      expect(lines, hasLength(1));
    });

    test('mergePayload updates invoice when remote is newer', () async {
      final oldTime = DateTime.now().toUtc().millisecondsSinceEpoch - 10000;
      final newTime = DateTime.now().toUtc().millisecondsSinceEpoch;

      // Insert existing invoice
      await db.insert(DbConstants.tableInvoice, {
        DbConstants.columnCustomerName: 'Old Customer',
        DbConstants.columnInvoiceDate: DateTime.now().toIso8601String(),
        DbConstants.columnInvoiceTotal: 100.00,
        DbConstants.columnInvoiceCurrency: 'USD',
        DbConstants.columnInvoiceDiscount: 0,
        DbConstants.columnUuid: 'invoice-uuid-001',
        DbConstants.columnUpdatedAt: oldTime,
      });

      final payload = SyncPayload(
        sourceDeviceId: 'remote-device',
        sourceDeviceName: 'Remote',
        timestamp: newTime,
        invoices: [
          {
            'uuid': 'invoice-uuid-001',
            'customer': 'New Customer',
            'date': DateTime.now().toIso8601String(),
            'total': 200.00,
            'currency': 'USD',
            'discount': 10.0,
            'updated_at': newTime,
            'lines': [],
          },
        ],
      );

      final result = await syncRepo.mergePayload(payload);

      expect(result.updated, 1);

      final invoices = await db.query(DbConstants.tableInvoice);
      expect(invoices.first['customer'], 'New Customer');
      expect(invoices.first['discount'], 10.0);
    });
  });
}
