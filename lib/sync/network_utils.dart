import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

class NetworkUtils {
  static final NetworkInfo _networkInfo = NetworkInfo();

  /// Get the device's local IP address on Wi-Fi
  static Future<String?> getLocalIpAddress() async {
    try {
      // Try network_info_plus first (works well on Android)
      final wifiIP = await _networkInfo.getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) {
        return wifiIP;
      }
    } catch (_) {}

    // Fallback: iterate network interfaces
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        // Skip loopback and docker interfaces
        if (interface.name.contains('lo') ||
            interface.name.contains('docker')) {
          continue;
        }

        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Check if an IP:port is reachable
  static Future<bool> isReachable(
    String ip,
    int port, {
    Duration? timeout,
  }) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: timeout ?? const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Validate IP address format
  static bool isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;

    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }
}
