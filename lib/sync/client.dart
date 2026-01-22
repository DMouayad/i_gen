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

  factory ClientState.success(SyncResult result, {String? message}) =>
      ClientState(
        status: ClientStatus.success,
        result: result,
        message: message ?? 'Sync complete!',
      );

  factory ClientState.error(String msg) =>
      ClientState(status: ClientStatus.error, message: msg);

  /// Check if a new sync can be started
  bool get canSync =>
      status == ClientStatus.idle ||
      status == ClientStatus.success ||
      status == ClientStatus.error;
}

class SyncClient {
  final SyncService _syncService;

  final _stateController = StreamController<ClientState>.broadcast();
  ClientState _currentState = ClientState.idle();

  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration syncTimeout = Duration(minutes: 5);

  SyncClient(this._syncService);

  Stream<ClientState> get stateStream => _stateController.stream;
  ClientState get currentState => _currentState;

  void _updateState(ClientState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Create a fresh HTTP client for each request
  http.Client _createClient() => http.Client();

  Future<DeviceInfo> _getDeviceInfo(String baseUrl) async {
    final client = _createClient();
    try {
      final response = await client
          .get(Uri.parse('$baseUrl/info'))
          .timeout(connectionTimeout);

      if (response.statusCode != 200) {
        throw Exception('Failed to connect: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return DeviceInfo.fromJson(json);
    } finally {
      client.close();
    }
  }

  Future<SyncResult> _sendSyncPayload(
    String baseUrl,
    SyncPayload payload,
  ) async {
    final client = _createClient();
    try {
      final response = await client
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
    } finally {
      client.close();
    }
  }

  Future<SyncResult> syncWith({required String ip, int port = 8080}) async {
    // Prevent double-tap
    if (_currentState.status == ClientStatus.connecting ||
        _currentState.status == ClientStatus.syncing) {
      return const SyncResult();
    }

    if (!NetworkUtils.isValidIp(ip)) {
      throw ArgumentError('Invalid IP address: $ip');
    }

    final baseUrl = 'http://$ip:$port';

    try {
      _updateState(ClientState.connecting('$ip:$port'));

      final deviceInfo = await _getDeviceInfo(baseUrl);
      _checkClockSkew(deviceInfo.currentTime);

      _updateState(ClientState.syncing('Preparing data...', 0.2));

      final payload = await _syncService.createPayload(deviceInfo.deviceId);
      final itemCount = _countItems(payload);

      if (itemCount == 0) {
        _updateState(
          ClientState.success(
            const SyncResult(),
            message: 'Already up to date - no changes to sync',
          ),
        );
        _scheduleResetToIdle();
        return const SyncResult();
      }

      _updateState(ClientState.syncing('Sending $itemCount items...', 0.5));

      final result = await _sendSyncPayload(baseUrl, payload);

      _updateState(ClientState.success(result));
      _scheduleResetToIdle();

      return result;
    } catch (e) {
      final errorMsg = _formatError(e);
      _updateState(ClientState.error(errorMsg));
      _scheduleResetToIdle(delay: const Duration(seconds: 5));
      rethrow;
    }
  }

  void _scheduleResetToIdle({Duration delay = const Duration(seconds: 3)}) {
    Future.delayed(delay, () {
      if (_currentState.status == ClientStatus.success ||
          _currentState.status == ClientStatus.error) {
        _updateState(ClientState.idle());
      }
    });
  }

  /// Manually reset state (can be called from UI)
  void reset() {
    _updateState(ClientState.idle());
  }

  void _checkClockSkew(int remoteTime) {
    final localTime = DateTime.now().toUtc().millisecondsSinceEpoch;
    final diff = (localTime - remoteTime).abs();
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

  Future<DeviceInfo?> testConnection(String ip, int port) async {
    try {
      final baseUrl = 'http://$ip:$port';
      return await _getDeviceInfo(baseUrl);
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _stateController.close();
  }
}
