// lib/sync/sync_service.dart

import 'dart:async';
import 'package:i_gen/sync/device_identity.dart';
import 'package:i_gen/sync/sync_models.dart';
import 'package:i_gen/sync/sync_repo.dart';

enum SyncStatus { idle, connecting, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final String message;
  final SyncResult? result;

  const SyncState({required this.status, this.message = '', this.result});

  factory SyncState.idle() => const SyncState(status: SyncStatus.idle);
  factory SyncState.connecting() =>
      const SyncState(status: SyncStatus.connecting, message: 'Connecting...');
  factory SyncState.syncing(String msg) =>
      SyncState(status: SyncStatus.syncing, message: msg);
  factory SyncState.success(SyncResult result) =>
      SyncState(status: SyncStatus.success, result: result);
  factory SyncState.error(String msg) =>
      SyncState(status: SyncStatus.error, message: msg);
}

class SyncService {
  final SyncRepository _repository;
  final _stateController = StreamController<SyncState>.broadcast();

  SyncService(this._repository);

  Stream<SyncState> get stateStream => _stateController.stream;

  void dispose() {
    _stateController.close();
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
    _stateController.add(
      SyncState.syncing('Merging ${_countItems(payload)} items...'),
    );

    try {
      final result = await _repository.mergePayload(payload);
      _stateController.add(SyncState.success(result));
      return result;
    } catch (e) {
      _stateController.add(SyncState.error('Merge failed: $e'));
      rethrow;
    }
  }

  /// Get device info for handshake
  Future<DeviceInfo> getDeviceInfo() async {
    return DeviceInfo(
      deviceId: await DeviceIdentity.getDeviceId(),
      deviceName: await DeviceIdentity.getDeviceName(),
      currentTime: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  int _countItems(SyncPayload payload) {
    return payload.products.length +
        payload.invoices.length +
        payload.priceCategories.length +
        payload.prices.length +
        payload.tombstones.length;
  }
}
