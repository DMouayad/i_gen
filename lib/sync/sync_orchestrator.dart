import 'dart:async';
import 'package:i_gen/sync/sync_service.dart';
import 'package:i_gen/sync/sync_preferences.dart';
import 'package:i_gen/sync/sync_models.dart';
import 'package:i_gen/sync/device_identity.dart';

enum AutoSyncStatus {
  idle,
  waitingForDevice,
  connecting,
  syncingOutbound,
  syncingInbound,
  completed,
  failed,
}

class AutoSyncState {
  final AutoSyncStatus status;
  final String message;
  final SyncResult? outboundResult;
  final SyncResult? inboundResult;
  final String? error;

  const AutoSyncState({
    required this.status,
    this.message = '',
    this.outboundResult,
    this.inboundResult,
    this.error,
  });

  factory AutoSyncState.idle() =>
      const AutoSyncState(status: AutoSyncStatus.idle, message: 'Ready');

  factory AutoSyncState.waiting() => const AutoSyncState(
    status: AutoSyncStatus.waitingForDevice,
    message: 'Waiting for device...',
  );

  factory AutoSyncState.connecting(String deviceName) => AutoSyncState(
    status: AutoSyncStatus.connecting,
    message: 'Connecting to $deviceName...',
  );

  factory AutoSyncState.syncingOutbound() => const AutoSyncState(
    status: AutoSyncStatus.syncingOutbound,
    message: 'Sending data...',
  );

  factory AutoSyncState.syncingInbound() => const AutoSyncState(
    status: AutoSyncStatus.syncingInbound,
    message: 'Receiving data...',
  );

  factory AutoSyncState.completed(SyncResult outbound, SyncResult inbound) =>
      AutoSyncState(
        status: AutoSyncStatus.completed,
        message: 'Sync complete!',
        outboundResult: outbound,
        inboundResult: inbound,
      );

  factory AutoSyncState.failed(String error) => AutoSyncState(
    status: AutoSyncStatus.failed,
    message: 'Sync failed',
    error: error,
  );

  /// Combined totals from both directions
  int get totalInserted =>
      (outboundResult?.inserted ?? 0) + (inboundResult?.inserted ?? 0);
  int get totalUpdated =>
      (outboundResult?.updated ?? 0) + (inboundResult?.updated ?? 0);
  int get totalDeleted =>
      (outboundResult?.deleted ?? 0) + (inboundResult?.deleted ?? 0);
}

class SyncOrchestrator {
  final SyncService _syncService;
  final SyncPreferences _preferences;

  final _stateController = StreamController<AutoSyncState>.broadcast();
  AutoSyncState _currentState = AutoSyncState.idle();

  StreamSubscription? _discoverySubscription;
  bool _isAutoSyncInProgress = false;

  SyncOrchestrator(this._syncService, this._preferences);

  Stream<AutoSyncState> get stateStream => _stateController.stream;
  AutoSyncState get currentState => _currentState;
  SyncPreferences get preferences => _preferences;

  void _updateState(AutoSyncState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Start watching for default device
  void startAutoSyncWatch() {
    if (!_preferences.autoSyncEnabled) return;

    final defaultDevice = _preferences.defaultDevice;
    if (defaultDevice == null) return;

    _updateState(AutoSyncState.waiting());

    // Listen for discovered devices
    _discoverySubscription?.cancel();
    _discoverySubscription = _syncService.discovery.devicesStream.listen((
      devices,
    ) {
      // Check if default device is available
      final found = devices
          .where((d) => d.deviceId == defaultDevice.deviceId)
          .firstOrNull;

      if (found != null && !_isAutoSyncInProgress) {
        // Default device found! Start auto-sync
        _performAutoSync(found.ip, found.port, found.name);
      }
    });

    // Start discovery
    _syncService.discovery.startDiscovery();
  }

  /// Stop watching for devices
  void stopAutoSyncWatch() {
    _discoverySubscription?.cancel();
    _discoverySubscription = null;
    _syncService.discovery.stopDiscovery();
    _updateState(AutoSyncState.idle());
  }

  /// Manually trigger bidirectional sync with default device
  Future<AutoSyncState> syncWithDefaultDevice() async {
    final defaultDevice = _preferences.defaultDevice;
    if (defaultDevice == null) {
      _updateState(AutoSyncState.failed('No default device configured'));
      return _currentState;
    }

    return await performBidirectionalSync(
      ip: defaultDevice.ip,
      port: defaultDevice.port,
      deviceName: defaultDevice.deviceName,
    );
  }

  /// Perform bidirectional sync with a specific device
  Future<AutoSyncState> performBidirectionalSync({
    required String ip,
    required int port,
    required String deviceName,
  }) async {
    if (_isAutoSyncInProgress) {
      return _currentState;
    }

    _isAutoSyncInProgress = true;

    try {
      _updateState(AutoSyncState.connecting(deviceName));

      // Step 1: Send our changes (outbound)
      _updateState(AutoSyncState.syncingOutbound());
      final outboundResult = await _syncService.client.syncWith(
        ip: ip,
        port: port,
      );

      // Step 2: Request their changes (inbound)
      _updateState(AutoSyncState.syncingInbound());
      final inboundResult = await _requestInboundSync(ip, port);

      // Step 3: Record success
      await _preferences.recordSyncTime();

      final finalState = AutoSyncState.completed(outboundResult, inboundResult);
      _updateState(finalState);

      return finalState;
    } catch (e) {
      final errorState = AutoSyncState.failed(e.toString());
      _updateState(errorState);
      return errorState;
    } finally {
      _isAutoSyncInProgress = false;

      // Reset to idle after delay
      Future.delayed(const Duration(seconds: 5), () {
        if (_currentState.status == AutoSyncStatus.completed ||
            _currentState.status == AutoSyncStatus.failed) {
          _updateState(AutoSyncState.idle());
        }
      });
    }
  }

  /// Internal auto-sync trigger
  Future<void> _performAutoSync(String ip, int port, String deviceName) async {
    await performBidirectionalSync(ip: ip, port: port, deviceName: deviceName);
  }

  /// Request the remote device to send us their changes
  Future<SyncResult> _requestInboundSync(String ip, int port) async {
    // Call the /pull endpoint on the remote server
    final deviceId = await DeviceIdentity.getDeviceId();
    final response = await _syncService.client.requestPull(
      ip: ip,
      port: port,
      requestingDeviceId: deviceId,
    );

    if (response != null) {
      return await _syncService.mergePayload(response);
    }

    return const SyncResult();
  }

  /// Check if sync is due and prompt user
  bool shouldPromptForSync() {
    return _preferences.autoSyncEnabled &&
        _preferences.defaultDevice != null &&
        _preferences.isSyncDue;
  }

  void dispose() {
    _discoverySubscription?.cancel();
    _stateController.close();
  }
}
