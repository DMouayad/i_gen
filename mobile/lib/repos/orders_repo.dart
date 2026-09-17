import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:i_gen/models/order.dart';

/// Live server reads for the shared orders domain (Phase 10).
///
/// Read-only by construction: this exposes SELECT paths only, so even a
/// modified client cannot sneak an order write through this seam. There is
/// no local cache, no outbox, and no sync — staff always see live data and
/// an explicit offline state instead of a cached phantom.
class OrdersRepo {
  OrdersRepo({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _client {
    if (_clientOverride != null) return _clientOverride;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured {
    try {
      Supabase.instance.client;
      return true;
    } catch (_) {
      return _clientOverride != null;
    }
  }

  /// Newest orders first. Throws [SocketException] offline so callers can
  /// show the retry state.
  Future<List<Order>> getOrders() async {
    final client = _client;
    if (client == null) throw const SocketException('Sync not configured');
    final rows = await client
        .from('orders')
        .select()
        .eq('is_deleted', false)
        .order('created_at', ascending: false)
        .limit(200);
    final orders = <Order>[];
    for (final row in (rows as List)) {
      final order = Order.fromMap(Map<String, dynamic>.from(row as Map));
      if (order != null) orders.add(order);
    }
    return orders;
  }

  Future<List<OrderItem>> getOrderItems(String orderId) async {
    final client = _client;
    if (client == null) throw const SocketException('Sync not configured');
    final rows = await client
        .from('order_items')
        .select()
        .eq('order_id', orderId);
    final items = <OrderItem>[];
    for (final row in (rows as List)) {
      final item = OrderItem.fromMap(Map<String, dynamic>.from(row as Map));
      if (item != null) items.add(item);
    }
    return items;
  }

  /// Staff directory: distributors only, alphabetical by English name.
  Future<List<Distributor>> getDistributors() async {
    final client = _client;
    if (client == null) throw const SocketException('Sync not configured');
    try {
      final rows = await client
          .from('profiles')
          .select('id, name_ar, name_en, phone')
          .eq('role', 'distributor')
          .order('name_en');
      final out = <Distributor>[];
      for (final row in (rows as List)) {
        final d = Distributor.fromMap(Map<String, dynamic>.from(row as Map));
        if (d != null) out.add(d);
      }
      return out;
    } catch (e) {
      debugPrint('OrdersRepo: distributors read failed: $e');
      rethrow;
    }
  }
}
