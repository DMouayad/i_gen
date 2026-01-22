import 'dart:async';
import 'package:i_gen/sync/device_identity.dart';
import 'package:i_gen/sync/network_discovery_service.dart';
import 'package:i_gen/sync/sync_models.dart';
import 'package:i_gen/sync/server.dart';
import 'package:i_gen/sync/client.dart';
import 'package:i_gen/sync/sync_repo.dart';

class SyncService {
  final SyncRepository _repository;

  late final SyncDiscovery discovery;
  late final SyncServer server;
  late final SyncClient client;

  SyncService(this._repository) {
    discovery = SyncDiscovery();
    server = SyncServer(this, discovery);
    client = SyncClient(this);
  }

  /// Create payload with changes since last sync with target device
  Future<SyncPayload> createPayload(String targetDeviceId) async {
    final deviceId = await DeviceIdentity.getDeviceId();
    final deviceName = await DeviceIdentity.getDeviceName();
    final anchor = await _repository.getLastSyncAnchor(targetDeviceId);

    return await _repository.getChangesSince(anchor, deviceId, deviceName);
  }

  /// Create full export payload (for first sync or manual export)
  Future<SyncPayload> createFullPayload() async {
    final deviceId = await DeviceIdentity.getDeviceId();
    final deviceName = await DeviceIdentity.getDeviceName();

    return await _repository.getChangesSince(0, deviceId, deviceName);
  }

  /// Merge incoming payload
  Future<SyncResult> mergePayload(SyncPayload payload) async {
    return await _repository.mergePayload(payload);
  }

  /// Get device info for handshake
  Future<DeviceInfo> getDeviceInfo() async {
    return DeviceInfo(
      deviceId: await DeviceIdentity.getDeviceId(),
      deviceName: await DeviceIdentity.getDeviceName(),
      currentTime: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  /// Get sync history
  Future<List<Map<String, dynamic>>> getSyncHistory() async {
    return await _repository.getSyncHistory();
  }

  void dispose() {
    discovery.dispose();
    server.dispose();
    client.dispose();
  }
}
