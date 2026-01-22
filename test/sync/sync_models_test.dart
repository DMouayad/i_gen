import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/sync/sync_models.dart';

void main() {
  group('SyncPayload', () {
    test('serializes to JSON correctly', () {
      final payload = SyncPayload(
        sourceDeviceId: 'device-123',
        sourceDeviceName: 'Test Device',
        timestamp: 1700000000000,
        products: [
          {
            'uuid': 'p1',
            'model': 'M1',
            'name': 'Product 1',
            'updated_at': 1000,
          },
        ],
        invoices: [],
        priceCategories: [],
        prices: [],
        tombstones: [
          Tombstone(tableName: 'product', uuid: 'deleted-1', deletedAt: 2000),
        ],
      );

      final json = payload.toJson();

      expect(json['source_device_id'], 'device-123');
      expect(json['source_device_name'], 'Test Device');
      expect(json['timestamp'], 1700000000000);
      expect(json['products'], hasLength(1));
      expect(json['tombstones'], hasLength(1));
    });

    test('deserializes from JSON correctly', () {
      final json = {
        'source_device_id': 'device-456',
        'source_device_name': 'Another Device',
        'timestamp': 1700000000000,
        'products': [
          {
            'uuid': 'p1',
            'model': 'M1',
            'name': 'Product 1',
            'updated_at': 1000,
          },
        ],
        'invoices': [],
        'price_categories': [],
        'prices': [],
        'tombstones': [
          {'table_name': 'product', 'uuid': 'deleted-1', 'deleted_at': 2000},
        ],
      };

      final payload = SyncPayload.fromJson(json);

      expect(payload.sourceDeviceId, 'device-456');
      expect(payload.sourceDeviceName, 'Another Device');
      expect(payload.products, hasLength(1));
      expect(payload.tombstones, hasLength(1));
      expect(payload.tombstones.first.uuid, 'deleted-1');
    });

    test('round-trip serialization preserves data', () {
      final original = SyncPayload(
        sourceDeviceId: 'device-789',
        sourceDeviceName: 'Round Trip Device',
        timestamp: 1700000000000,
        products: [
          {
            'uuid': 'p1',
            'model': 'M1',
            'name': 'Product 1',
            'updated_at': 1000,
          },
          {
            'uuid': 'p2',
            'model': 'M2',
            'name': 'Product 2',
            'updated_at': 2000,
          },
        ],
        invoices: [
          {
            'uuid': 'i1',
            'customer': 'Customer 1',
            'total': 100.0,
            'updated_at': 3000,
          },
        ],
        priceCategories: [],
        prices: [],
        tombstones: [],
      );

      final json = original.toJson();
      final restored = SyncPayload.fromJson(json);

      expect(restored.sourceDeviceId, original.sourceDeviceId);
      expect(restored.products.length, original.products.length);
      expect(restored.invoices.length, original.invoices.length);
    });
  });

  group('Tombstone', () {
    test('serializes correctly', () {
      final tombstone = Tombstone(
        tableName: 'product',
        uuid: 'uuid-123',
        deletedAt: 1700000000000,
      );

      final json = tombstone.toJson();

      expect(json['table_name'], 'product');
      expect(json['uuid'], 'uuid-123');
      expect(json['deleted_at'], 1700000000000);
    });

    test('deserializes correctly', () {
      final json = {
        'table_name': 'invoice',
        'uuid': 'uuid-456',
        'deleted_at': 1700000000000,
      };

      final tombstone = Tombstone.fromJson(json);

      expect(tombstone.tableName, 'invoice');
      expect(tombstone.uuid, 'uuid-456');
      expect(tombstone.deletedAt, 1700000000000);
    });
  });

  group('SyncResult', () {
    test('addition operator combines results', () {
      final result1 = SyncResult(
        inserted: 5,
        updated: 3,
        deleted: 1,
        skipped: 2,
      );
      final result2 = SyncResult(
        inserted: 2,
        updated: 1,
        deleted: 0,
        skipped: 4,
      );

      final combined = result1 + result2;

      expect(combined.inserted, 7);
      expect(combined.updated, 4);
      expect(combined.deleted, 1);
      expect(combined.skipped, 6);
    });

    test('combines error lists', () {
      final result1 = SyncResult(errors: ['Error 1']);
      final result2 = SyncResult(errors: ['Error 2', 'Error 3']);

      final combined = result1 + result2;

      expect(combined.errors, ['Error 1', 'Error 2', 'Error 3']);
    });
  });

  group('DeviceInfo', () {
    test('serializes correctly', () {
      final info = DeviceInfo(
        deviceId: 'device-id',
        deviceName: 'Device Name',
        currentTime: 1700000000000,
        protocolVersion: 1,
      );

      final json = info.toJson();

      expect(json['device_id'], 'device-id');
      expect(json['device_name'], 'Device Name');
      expect(json['current_time'], 1700000000000);
      expect(json['protocol_version'], 1);
    });

    test('deserializes correctly', () {
      final json = {
        'device_id': 'device-id',
        'device_name': 'Device Name',
        'current_time': 1700000000000,
        'protocol_version': 1,
      };

      final info = DeviceInfo.fromJson(json);

      expect(info.deviceId, 'device-id');
      expect(info.deviceName, 'Device Name');
      expect(info.currentTime, 1700000000000);
      expect(info.protocolVersion, 1);
    });
  });
}
