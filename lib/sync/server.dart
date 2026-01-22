import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:i_gen/sync/sync_models.dart';
import 'package:i_gen/sync/sync_service.dart';
import 'package:i_gen/sync/network_utils.dart';

import 'network_discovery_service.dart';

enum ServerStatus { stopped, starting, running, error }

class ServerState {
  final ServerStatus status;
  final String? ip;
  final int? port;
  final String? error;
  final SyncResult? lastResult;

  const ServerState({
    required this.status,
    this.ip,
    this.port,
    this.error,
    this.lastResult,
  });

  factory ServerState.stopped() =>
      const ServerState(status: ServerStatus.stopped);
  factory ServerState.starting() =>
      const ServerState(status: ServerStatus.starting);
  factory ServerState.running(String ip, int port) =>
      ServerState(status: ServerStatus.running, ip: ip, port: port);
  factory ServerState.error(String msg) =>
      ServerState(status: ServerStatus.error, error: msg);

  String get displayAddress =>
      status == ServerStatus.running ? '$ip:$port' : 'Not running';
}

class SyncServer {
  final SyncService _syncService;
  final SyncDiscovery _discovery;

  HttpServer? _server;
  final _stateController = StreamController<ServerState>.broadcast();
  ServerState _currentState = ServerState.stopped();

  static const int defaultPort = 8080;

  SyncServer(this._syncService, this._discovery);

  Stream<ServerState> get stateStream => _stateController.stream;
  ServerState get currentState => _currentState;
  bool get isRunning => _currentState.status == ServerStatus.running;

  void _updateState(ServerState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Start the sync server
  Future<void> start({int port = defaultPort}) async {
    if (isRunning) {
      throw StateError('Server is already running');
    }

    _updateState(ServerState.starting());

    try {
      // Get local IP
      final ip = await NetworkUtils.getLocalIpAddress();
      if (ip == null) {
        throw Exception(
          'Could not determine local IP address. Check Wi-Fi connection.',
        );
      }

      // Create router
      final router = Router();

      // GET /info - Device info & handshake
      router.get('/info', _handleInfo);

      // POST /sync - Receive sync data
      router.post('/sync', _handleSync);

      // GET /health - Simple health check
      router.get('/health', (Request req) => Response.ok('OK'));

      // Add CORS and logging middleware
      final handler = const Pipeline()
          .addMiddleware(_corsMiddleware())
          .addMiddleware(logRequests())
          .addHandler(router.call);

      // Start server
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);

      // Start advertising via mDNS
      await _discovery.startAdvertising(port: port);

      _updateState(ServerState.running(ip, port));
    } catch (e) {
      _updateState(ServerState.error(e.toString()));
      rethrow;
    }
  }

  /// Stop the server
  Future<void> stop() async {
    await _discovery.stopAdvertising();
    await _server?.close();
    _server = null;
    _updateState(ServerState.stopped());
  }

  /// Handle GET /info
  Future<Response> _handleInfo(Request request) async {
    try {
      final info = await _syncService.getDeviceInfo();
      return Response.ok(
        jsonEncode(info.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  }

  /// Handle POST /sync
  Future<Response> _handleSync(Request request) async {
    try {
      print('📥 Received sync request');

      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final payload = SyncPayload.fromJson(json);

      final itemCount =
          payload.products.length +
          payload.invoices.length +
          payload.priceCategories.length +
          payload.prices.length;

      print(
        '📥 Receiving sync from ${payload.sourceDeviceName}: $itemCount items',
      );

      final result = await _syncService.mergePayload(payload);

      print('✅ Sync complete: $result');

      // Update state but keep server running
      _updateState(
        ServerState(
          status: ServerStatus.running,
          ip: _currentState.ip,
          port: _currentState.port,
          lastResult: result,
        ),
      );

      return Response.ok(
        jsonEncode({
          'success': true,
          'result': {
            'inserted': result.inserted,
            'updated': result.updated,
            'deleted': result.deleted,
            'skipped': result.skipped,
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stack) {
      print('❌ Sync error: $e');
      print(stack);

      // Don't change server state on error - keep running
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// CORS middleware for cross-origin requests
  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }

        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type',
  };

  void dispose() {
    stop();
    _stateController.close();
  }
}
