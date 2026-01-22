import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:i_gen/sync/device_identity.dart';

/// Represents a discovered sync device
class DiscoveredDevice {
  final String name;
  final String ip;
  final int port;
  final String deviceId;
  final DateTime discoveredAt;

  const DiscoveredDevice({
    required this.name,
    required this.ip,
    required this.port,
    required this.deviceId,
    required this.discoveredAt,
  });

  @override
  bool operator ==(Object other) =>
      other is DiscoveredDevice && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}

class SyncDiscovery {
  static const String _serviceType = '_igensync._tcp';
  static const String _serviceName = 'igen_sync';

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  final _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();
  final Map<String, DiscoveredDevice> _devices = {};

  Stream<List<DiscoveredDevice>> get devicesStream => _devicesController.stream;
  List<DiscoveredDevice> get devices => _devices.values.toList();

  /// Start advertising this device as a sync server
  Future<void> startAdvertising({required int port}) async {
    await stopAdvertising();

    final deviceName = await DeviceIdentity.getDeviceName();
    final deviceId = await DeviceIdentity.getDeviceId();

    final service = BonsoirService(
      name: '$_serviceName-$deviceName',
      type: _serviceType,
      port: port,
      attributes: {'deviceId': deviceId, 'deviceName': deviceName},
    );

    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();

    debugPrint('📢 Advertising sync service: ${service.name} on port $port');
  }

  /// Stop advertising
  Future<void> stopAdvertising() async {
    await _broadcast?.stop();
    _broadcast = null;
  }

  /// Start discovering other sync servers
  Future<void> startDiscovery() async {
    await stopDiscovery();

    _discovery = BonsoirDiscovery(type: _serviceType);
    await _discovery!.initialize();

    _discovery!.eventStream?.listen(_onDiscoveryEvent);

    await _discovery!.start();
    debugPrint('🔍 Started discovering sync services...');
  }

  void _onDiscoveryEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent():
        // Service found - in v6, we need to resolve it
        event.service.resolve(_discovery!.serviceResolver);
        break;

      case BonsoirDiscoveryServiceResolvedEvent():
        final service = event.service;
        _onServiceResolved(service);
        break;

      case BonsoirDiscoveryServiceLostEvent():
        _onServiceLost(event.service);
        break;

      default:
        break;
    }
  }

  Future<void> _onServiceResolved(BonsoirService service) async {
    final deviceId = service.attributes['deviceId'];
    final deviceName = service.attributes['deviceName'] ?? service.name;
    final ip = service.host;
    final port = service.port;

    if (deviceId == null || ip == null) return;

    // Don't add ourselves
    final myId = await DeviceIdentity.getDeviceId();
    if (deviceId == myId) return;

    final device = DiscoveredDevice(
      name: deviceName,
      ip: ip,
      port: port,
      deviceId: deviceId,
      discoveredAt: DateTime.now(),
    );

    _devices[deviceId] = device;
    _devicesController.add(devices);

    debugPrint('✅ Discovered: $deviceName at $ip:$port');
  }

  void _onServiceLost(BonsoirService? service) {
    final deviceId = service?.attributes['deviceId'];
    if (deviceId != null && _devices.containsKey(deviceId)) {
      final removed = _devices.remove(deviceId);
      _devicesController.add(devices);
      debugPrint('❌ Lost: ${removed?.name}');
    }
  }

  /// Stop discovery
  Future<void> stopDiscovery() async {
    await _discovery?.stop();
    _discovery = null;
    _devices.clear();
    _devicesController.add([]);
  }

  /// Refresh discovery (restart)
  Future<void> refresh() async {
    await stopDiscovery();
    await startDiscovery();
  }

  void dispose() {
    stopAdvertising();
    stopDiscovery();
    _devicesController.close();
  }
}
