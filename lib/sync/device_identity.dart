import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentity {
  static const _keyDeviceId = 'sync_device_id';
  static const _keyDeviceName = 'sync_device_name';

  static String? _cachedId;
  static String? _cachedName;

  /// Get or create a unique device ID
  static Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_keyDeviceId);

    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_keyDeviceId, id);
    }

    _cachedId = id;
    return id;
  }

  /// Get or create a friendly device name
  static Future<String> getDeviceName() async {
    if (_cachedName != null) return _cachedName!;

    final prefs = await SharedPreferences.getInstance();
    var name = prefs.getString(_keyDeviceName);

    if (name == null) {
      name = _generateDefaultName();
      await prefs.setString(_keyDeviceName, name);
    }

    _cachedName = name;
    return name;
  }

  static String _generateDefaultName() {
    final suffix = DateTime.now().millisecondsSinceEpoch % 10000;
    if (Platform.isAndroid) return 'Android-$suffix';
    if (Platform.isWindows) return 'Windows-$suffix';
    if (Platform.isIOS) return 'iOS-$suffix';
    if (Platform.isMacOS) return 'Mac-$suffix';
    return 'Device-$suffix';
  }

  static Future<void> setDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDeviceName, name);
    _cachedName = name;
  }
}
