import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// New-order event source (Phase 11). Thin seam over the Supabase Realtime
/// INSERT subscription on `orders` so the watcher is unit-testable without
/// a socket: production uses [SupabaseOrderEvents], tests use
/// [FakeOrderEvents].
abstract class OrderEvents {
  /// Raw INSERT payloads (server row maps). Listen only while subscribed.
  Stream<Map<String, dynamic>> get onOrderInserted;

  /// Opens the channel subscription. Idempotent; no-ops when unconfigured.
  Future<void> subscribe();

  /// Closes the channel subscription. Idempotent.
  Future<void> unsubscribe();

  void dispose();
}

/// Live Realtime INSERT feed on `public.orders` (RLS is the lock: staff see
/// all rows, so the staff-gated watcher only ever receives visible rows).
/// Requires the table in the `supabase_realtime` publication (dashboard SQL,
/// done once) — without it subscribe succeeds but no events ever arrive.
/// Note: INSERT payloads always carry the full row (`newRecord`); replica
/// identity only matters for UPDATE/DELETE, which this watcher never uses.
class SupabaseOrderEvents implements OrderEvents {
  SupabaseOrderEvents({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  RealtimeChannel? _channel;

  SupabaseClient? get _client {
    if (_clientOverride != null) return _clientOverride;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<Map<String, dynamic>> get onOrderInserted => _controller.stream;

  @override
  Future<void> subscribe() async {
    if (_channel != null) return;
    final client = _client;
    if (client == null) {
      debugPrint('OrderEvents: Supabase unconfigured, skipping subscribe.');
      return;
    }
    try {
      final channel = client.channel('orders-staff');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'orders',
        callback: (payload) {
          if (!_controller.isClosed) {
            _controller.add(Map<String, dynamic>.from(payload.newRecord));
          }
        },
      );
      channel.subscribe();
      _channel = channel;
    } catch (e) {
      debugPrint('OrderEvents: subscribe failed: $e');
    }
  }

  @override
  Future<void> unsubscribe() async {
    final channel = _channel;
    _channel = null;
    if (channel == null) return;
    try {
      await _client?.removeChannel(channel);
    } catch (e) {
      debugPrint('OrderEvents: unsubscribe failed: $e');
    }
  }

  @override
  void dispose() {
    unawaited(unsubscribe());
    _controller.close();
  }
}

/// In-memory event source for tests: the test pushes rows via [emit].
class FakeOrderEvents implements OrderEvents {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  int subscribes = 0;
  int unsubscribes = 0;

  @override
  Stream<Map<String, dynamic>> get onOrderInserted => _controller.stream;

  void emit(Map<String, dynamic> row) => _controller.add(row);

  @override
  Future<void> subscribe() async {
    subscribes++;
  }

  @override
  Future<void> unsubscribe() async {
    unsubscribes++;
  }

  @override
  void dispose() {
    if (!_controller.isClosed) _controller.close();
  }
}
