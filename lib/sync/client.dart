// lib/sync/sync_client.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:i_gen/sync/sync_models.dart';
import 'package:i_gen/sync/sync_service.dart';
import 'package:i_gen/sync/network_utils.dart';

enum ClientStatus { idle, connecting, syncing, success, error }

class ClientState {
  final ClientStatus status;
  final String message;
  final SyncResult? result;
  final double? progress;

  const ClientState({
    required this.status,
    this.message = '',
    this.result,
    this.progress,
  });

  factory ClientState.idle() => const ClientState(status: ClientStatus.idle);
  factory ClientState.connecting(String target) => ClientState(
    status: ClientStatus.connecting,
    message: 'Connecting to $target...',
  );
  factory ClientState.syncing(String msg, [double? progress]) => ClientState(
    status: ClientStatus.syncing,
    message: msg,
    progress: progress,
  );
  factory ClientState.success(SyncResult result) => ClientState(
    status: ClientStatus.success,
    result: result,
    message: 'Sync complete!',
  );
  factory ClientState.error(String msg) =>
      ClientState(status: ClientStatus.error, message: msg);
}

class SyncClient {
  final SyncService _syncService;
  final http.Client _httpClient;

  final _stateController = StreamController<ClientState>.broadcast();
  ClientState _currentState = ClientState.idle();

  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration syncTimeout = Duration(minutes: 5);

  SyncClient(this._syncService) : _httpClient = http.Client();

  Stream<ClientState> get stateStream => _stateController.stream;
  ClientState get currentState => _currentState;

  void _updateState(ClientState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Sync with a remote device
  Future<SyncResult> syncWith({required String ip, int port = 8080}) async {
    if (!NetworkUtils.isValidIp(ip)) {
      throw ArgumentError('Invalid IP address: $ip');
    }

    final baseUrl = 'http://$ip:$port';

    try {
      // Step 1: Connect and get device info
      _updateState(ClientState.connecting('$ip:$port'));

      final deviceInfo = await _getDeviceInfo(baseUrl);

      // Check for clock skew
      _checkClockSkew(deviceInfo.currentTime);

      // Step 2: Create sync payload
      _updateState(ClientState.syncing('Preparing data...', 0.2));

      final payload = await _syncService.createPayload(deviceInfo.deviceId);
      print(payload.toJson());
      final itemCount = _countItems(payload);
      if (itemCount == 0) {
        _updateState(ClientState.success(const SyncResult()));
        return const SyncResult();
      }

      // Step 3: Send sync data
      _updateState(ClientState.syncing('Sending $itemCount items...', 0.5));

      final result = await _sendSyncPayload(baseUrl, payload);

      // Step 4: Success
      _updateState(ClientState.success(result));

      return result;
    } catch (e) {
      final errorMsg = _formatError(e);
      _updateState(ClientState.error(errorMsg));
      rethrow;
    }
  }

  /// Get device info from server
  Future<DeviceInfo> _getDeviceInfo(String baseUrl) async {
    final response = await _httpClient
        .get(Uri.parse('$baseUrl/info'))
        .timeout(connectionTimeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to connect: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return DeviceInfo.fromJson(json);
  }

  /// Send sync payload to server
  Future<SyncResult> _sendSyncPayload(
    String baseUrl,
    SyncPayload payload,
  ) async {
    final response = await _httpClient
        .post(
          Uri.parse('$baseUrl/sync'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload.toJson()),
        )
        .timeout(syncTimeout);

    if (response.statusCode != 200) {
      final error = _parseErrorResponse(response);
      throw Exception('Sync failed: $error');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    if (json['success'] != true) {
      throw Exception('Sync rejected: ${json['error']}');
    }

    final resultJson = json['result'] as Map<String, dynamic>;
    return SyncResult(
      inserted: resultJson['inserted'] as int? ?? 0,
      updated: resultJson['updated'] as int? ?? 0,
      deleted: resultJson['deleted'] as int? ?? 0,
      skipped: resultJson['skipped'] as int? ?? 0,
    );
  }

  /// Check if there's significant clock skew
  void _checkClockSkew(int remoteTime) {
    final localTime = DateTime.now().toUtc().millisecondsSinceEpoch;
    final diff = (localTime - remoteTime).abs();

    // Warn if clocks differ by more than 1 minute
    if (diff > 60000) {
      print('⚠️ Warning: Clock skew detected (${diff ~/ 1000} seconds)');
    }
  }

  int _countItems(SyncPayload payload) {
    return payload.products.length +
        payload.invoices.length +
        payload.priceCategories.length +
        payload.prices.length +
        payload.tombstones.length;
  }

  String _parseErrorResponse(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return json['error'] as String? ?? 'Unknown error';
    } catch (_) {
      return response.body;
    }
  }

  String _formatError(dynamic error) {
    if (error is http.ClientException) {
      return 'Connection failed: ${error.message}';
    }
    if (error is TimeoutException) {
      return 'Connection timed out';
    }
    if (error is SocketException) {
      return 'Network error: ${error.message}';
    }
    return error.toString();
  }

  /// Test connection to a device
  Future<DeviceInfo?> testConnection(String ip, int port) async {
    try {
      final baseUrl = 'http://$ip:$port';
      return await _getDeviceInfo(baseUrl);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _httpClient.close();
    _stateController.close();
  }
}
