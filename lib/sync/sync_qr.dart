// lib/sync/sync_qr.dart

import 'dart:convert';

class SyncQrData {
  final String ip;
  final int port;
  final String deviceName;
  final String deviceId;

  const SyncQrData({
    required this.ip,
    required this.port,
    required this.deviceName,
    required this.deviceId,
  });

  /// Encode to QR string
  String encode() {
    return jsonEncode({
      'type': 'igen_sync', // App identifier
      'ip': ip,
      'port': port,
      'name': deviceName,
      'id': deviceId,
    });
  }

  /// Decode from QR string
  static SyncQrData? decode(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;

      // Validate it's our QR code
      if (json['type'] != 'igen_sync') return null;

      return SyncQrData(
        ip: json['ip'] as String,
        port: json['port'] as int,
        deviceName: json['name'] as String? ?? 'Unknown',
        deviceId: json['id'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
