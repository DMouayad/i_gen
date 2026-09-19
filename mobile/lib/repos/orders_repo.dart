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

  /// Newest orders first, with lines + product models embedded so the list
  /// can summarize each order in one round trip (no N+1 detail fetches).
  /// Throws [SocketException] offline so callers can show the retry state.
  Future<List<Order>> getOrders() async {
    final client = _client;
    if (client == null) throw const SocketException('Sync not configured');
    final rows = await client
        .from('orders')
        .select('*, order_items(*, products(model))')
        .eq('is_deleted', false)
        .order('created_at', ascending: false)
        .limit(200);
    final orders = <Order>[];
    for (final row in (rows as List)) {
      final map = Map<String, dynamic>.from(row as Map);
      final order = Order.fromMap(map, items: _parseItems(map['order_items']));
      if (order != null) orders.add(order);
    }
    return orders;
  }

  static List<OrderItem> _parseItems(Object? embedded) {
    final items = <OrderItem>[];
    for (final row in (embedded as List?) ?? const []) {
      final item = OrderItem.fromMap(Map<String, dynamic>.from(row as Map));
      if (item != null) items.add(item);
    }
    return items;
  }

  /// Lines with the product model embedded (`products(model)` via the
  /// `product_id` FK) so the details table can name each line. Staff can
  /// read the catalog, so the join is permitted; a missing embed degrades
  /// to a null model, never to a dropped line.
  /// Per-order refresh fallback (the list query embeds lines, so the dialog
  /// normally needs no second fetch). Kept deliberately: the embedded list
  /// is capped at 200 orders and goes stale — do not "clean up".
  Future<List<OrderItem>> getOrderItems(String orderId) async {
    final client = _client;
    if (client == null) throw const SocketException('Sync not configured');
    final rows = await client
        .from('order_items')
        .select('*, products(model)')
        .eq('order_id', orderId);
    final items = <OrderItem>[];
    for (final row in (rows as List)) {
      final item = OrderItem.fromMap(Map<String, dynamic>.from(row as Map));
      if (item != null) items.add(item);
    }
    return items;
  }

  /// Staff directory: customers only, alphabetical by English name.
  Future<List<Customer>> getCustomers() async {
    final client = _client;
    if (client == null) throw const SocketException('Sync not configured');
    try {
      final rows = await client
          .from('profiles')
          .select('id, name_ar, name_en, phone')
          .eq('role', 'customer')
          .order('name_en');
      final out = <Customer>[];
      for (final row in (rows as List)) {
        final d = Customer.fromMap(Map<String, dynamic>.from(row as Map));
        if (d != null) out.add(d);
      }
      return out;
    } catch (e) {
      debugPrint('OrdersRepo: customers read failed: $e');
      rethrow;
    }
  }
}
