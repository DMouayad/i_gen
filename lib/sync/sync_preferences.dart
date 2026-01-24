import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SyncDeviceConfig {
  final String deviceId;
  final String deviceName;
  final String ip;
  final int port;

  const SyncDeviceConfig({
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    required this.port,
  });

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'device_name': deviceName,
    'ip': ip,
    'port': port,
  };

  factory SyncDeviceConfig.fromJson(Map<String, dynamic> json) {
    return SyncDeviceConfig(
      deviceId: json['device_id'] as String,
      deviceName: json['device_name'] as String,
      ip: json['ip'] as String,
      port: json['port'] as int,
    );
  }
}

class SyncPreferences {
  static const _keyDefaultDevice = 'sync_default_device';
  static const _keyAutoSyncEnabled = 'sync_auto_enabled';
  static const _keyLastSyncTime = 'sync_last_time';
  static const _keySyncIntervalHours = 'sync_interval_hours';

  final SharedPreferences _prefs;

  SyncPreferences(this._prefs);

  /// Get default sync device
  SyncDeviceConfig? get defaultDevice {
    final json = _prefs.getString(_keyDefaultDevice);
    if (json == null) return null;
    try {
      return SyncDeviceConfig.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  /// Set default sync device
  Future<void> setDefaultDevice(SyncDeviceConfig? device) async {
    if (device == null) {
      await _prefs.remove(_keyDefaultDevice);
    } else {
      await _prefs.setString(_keyDefaultDevice, jsonEncode(device.toJson()));
    }
  }

  /// Check if auto-sync is enabled
  bool get autoSyncEnabled => _prefs.getBool(_keyAutoSyncEnabled) ?? false;

  /// Enable/disable auto-sync
  Future<void> setAutoSyncEnabled(bool enabled) async {
    await _prefs.setBool(_keyAutoSyncEnabled, enabled);
  }

  /// Get last successful sync time
  DateTime? get lastSyncTime {
    final ms = _prefs.getInt(_keyLastSyncTime);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Record sync time
  Future<void> recordSyncTime() async {
    await _prefs.setInt(
      _keyLastSyncTime,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Get sync interval in hours (default: 24)
  int get syncIntervalHours => _prefs.getInt(_keySyncIntervalHours) ?? 24;

  /// Set sync interval
  Future<void> setSyncIntervalHours(int hours) async {
    await _prefs.setInt(_keySyncIntervalHours, hours);
  }

  /// Check if sync is due
  bool get isSyncDue {
    final last = lastSyncTime;
    if (last == null) return true;

    final hoursSinceLastSync = DateTime.now().difference(last).inHours;
    return hoursSinceLastSync >= syncIntervalHours;
  }

  /// Check if a device is the default device
  bool isDefaultDevice(String deviceId) {
    return defaultDevice?.deviceId == deviceId;
  }
}
