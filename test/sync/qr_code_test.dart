// test/sync/sync_qr_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/sync/sync_qr.dart';

void main() {
  group('SyncQrData', () {
    test('encodes to JSON string', () {
      final qrData = SyncQrData(
        ip: '192.168.1.100',
        port: 8080,
        deviceName: 'Test Device',
        deviceId: 'device-123',
      );

      final encoded = qrData.encode();

      expect(encoded, contains('igen_sync'));
      expect(encoded, contains('192.168.1.100'));
      expect(encoded, contains('8080'));
      expect(encoded, contains('Test Device'));
    });

    test('decodes valid QR data', () {
      final original = SyncQrData(
        ip: '192.168.1.100',
        port: 8080,
        deviceName: 'Test Device',
        deviceId: 'device-123',
      );

      final encoded = original.encode();
      final decoded = SyncQrData.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.ip, '192.168.1.100');
      expect(decoded.port, 8080);
      expect(decoded.deviceName, 'Test Device');
      expect(decoded.deviceId, 'device-123');
    });

    test('returns null for invalid QR data', () {
      expect(SyncQrData.decode(''), isNull);
      expect(SyncQrData.decode('not json'), isNull);
      expect(SyncQrData.decode('{}'), isNull);
      expect(SyncQrData.decode('{"type": "wrong_type"}'), isNull);
    });

    test('returns null for QR data with wrong type', () {
      final wrongType =
          '{"type": "other_app", "ip": "192.168.1.1", "port": 8080}';
      expect(SyncQrData.decode(wrongType), isNull);
    });
  });
}
