import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/auth/supabase_config.dart';
import 'package:i_gen/l10n/app_localizations.dart';
import 'package:i_gen/l10n/app_localizations_en.dart';
import 'package:i_gen/models/order.dart';
import 'package:i_gen/repos/orders_repo.dart';
import 'package:i_gen/utils/locale_controller.dart';

import 'order_events.dart';
import 'order_notifier.dart';

/// Watches for new customer orders and raises one tray alert per order
/// (Phase 11): a Realtime INSERT subscription for the instant path plus a
/// periodic [OrdersRepo] poll as the gap fallback, behind one dedupe gate.
///
/// Staff-only (admin/employee): subscribes and polls while a staffer is
/// signed in with Supabase configured; stops on logout, role change away
/// from staff, or missing configuration. Customers and signed-out users
/// never subscribe, never poll, and never see a permission prompt.
///
/// Dedupe: every alerted order id is persisted in [SharedPreferences]
/// **before** notifying, so Realtime + poll + restart can never double-buzz.
/// The first run baselines silently (current orders become seen, no flood).
/// Only `pending` orders notify. Backlog floods are capped ([maxAlertsPerPoll]
// most recent); the cursor still jumps past all seen rows.
class OrderWatcher {
  OrderWatcher({
    required this._events,
    required this._notifier,
    required this._fetchOrders,
    required this._prefs,
    Future<AppLocalizations> Function()? copyLoader,
    this.pollInterval = const Duration(seconds: 60),
    this.maxAlertsPerPoll = 5,
  }) : _copyLoader = copyLoader ?? _defaultCopyLoader;

  final OrderEvents _events;
  final OrderNotifier _notifier;
  final Future<List<Order>> Function() _fetchOrders;
  final SharedPreferences _prefs;
  final Future<AppLocalizations> Function() _copyLoader;
  final Duration pollInterval;
  final int maxAlertsPerPoll;

  static const _kSeenIds = 'order_watcher_seen_ids';
  static const _kSeenCap = 200;

  StreamSubscription<UserRole?>? _roleSub;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  Timer? _poll;
  bool _active = false;
  bool _disposed = false;
  bool _eventsDisposed = false;
  // Invalidates in-flight async continuations across rapid role flaps
  // (staff→logout→staff): every _activate captures the generation and bails
  // after each await when it changed, so a stale continuation can never
  // steal the live subscription or leak a second poll timer.
  int _generation = 0;
  int _pollGeneration = -1;
  final Set<String> _seen = {};

  // delegate.load throws on unsupported locales; the app only ships en/ar,
  // so anything else falls back to English instead of silencing all alerts.
  static Future<AppLocalizations> _defaultCopyLoader() async {
    final code = LocaleController.instance.currentCode;
    final locale = code == 'ar' ? const Locale('ar') : const Locale('en');
    try {
      return await AppLocalizations.delegate.load(locale);
    } catch (_) {
      return AppLocalizationsEn();
    }
  }

  /// Starts role-gated watching. Never throws; safe to call twice (re-bind
  /// replaces the previous subscription). Mirrors [SyncBootstrap.wire].
  Future<void> bind(Stream<UserRole?> roles, UserRole? initialRole) async {
    try {
      await _roleSub?.cancel();
    } catch (_) {}
    _roleSub = null;
    if (_disposed) return;
    _loadSeen();
    _onRole(initialRole);
    try {
      _roleSub = roles.listen(
        _onRole,
        onError: (Object e) {
          debugPrint('OrderWatcher: role stream failed: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('OrderWatcher: role subscription failed: $e');
    }
  }

  static bool _isStaff(UserRole? role) =>
      role == UserRole.admin || role == UserRole.employee;

  void _onRole(UserRole? role) {
    if (_disposed) return;
    if (_isStaff(role)) {
      unawaited(_activate());
    } else {
      unawaited(_deactivate());
    }
  }

  Future<void> _activate() async {
    if (_active || _disposed) return;
    _active = true;
    final gen = ++_generation;
    bool stale() => gen != _generation || _disposed;
    try {
      await _notifier.initialize();
      await _notifier.requestPermission();
    } catch (e) {
      debugPrint('OrderWatcher: notifier setup failed: $e');
    }
    if (stale()) return;
    // Baseline silently: today's orders must not buzz on first run.
    await _pollOnce(notify: false);
    if (stale() || !_active) return;
    try {
      // Cancel-then-subscribe: never double-listen, even across flaps.
      await _eventsSub?.cancel();
      _eventsSub = null;
      await _events.subscribe();
      if (stale() || !_active) return;
      _eventsSub = _events.onOrderInserted.listen(
        _onEventRow,
        onError: (Object e) {
          debugPrint('OrderWatcher: event stream failed: $e');
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('OrderWatcher: event subscribe failed: $e');
    }
    if (stale() || !_active) return;
    _poll?.cancel();
    _pollGeneration = gen;
    _poll = Timer.periodic(pollInterval, (_) {
      if (_pollGeneration == _generation) _pollOnce(notify: true);
    });
  }

  Future<void> _deactivate() async {
    ++_generation;
    _active = false;
    _poll?.cancel();
    _poll = null;
    try {
      await _eventsSub?.cancel();
    } catch (_) {}
    _eventsSub = null;
    try {
      await _events.unsubscribe();
    } catch (e) {
      debugPrint('OrderWatcher: unsubscribe failed: $e');
    }
  }

  void _loadSeen() {
    try {
      _seen
        ..clear()
        ..addAll(_prefs.getStringList(_kSeenIds) ?? const []);
    } catch (e) {
      debugPrint('OrderWatcher: load seen failed: $e');
    }
  }

  Future<void> _persistSeen() async {
    try {
      // Pruned by insertion order (oldest marks first): the window the poll
      // refetches is the newest 200 rows, so an evicted id can only re-buzz
      // if it falls out of the seen set while still inside that window —
      // accepted as negligible (documented in the phase-11 spec).
      final capped = _seen.length <= _kSeenCap
          ? _seen.toList()
          : _seen.skip(_seen.length - _kSeenCap).toList();
      await _prefs.setStringList(_kSeenIds, capped);
    } catch (e) {
      debugPrint('OrderWatcher: persist seen failed: $e');
    }
  }

  bool _isFresh(Order order) =>
      order.status == 'pending' && !_seen.contains(order.id);

  /// Marks seen + persists BEFORE notifying, so a crash between the two
  /// loses at most one alert and a crash before loses none (re-alert once).
  Future<void> _alert(Order order) async {
    _seen.add(order.id);
    await _persistSeen();
    await _notify(order);
  }

  Future<void> _notify(Order order) async {
    try {
      final copy = await _copyLoader();
      await _notifier.showNewOrder(
        orderId: order.id,
        title: copy.newOrderTitle,
        body: copy.newOrderBody(order.total.toString(), order.currency),
        channelName: copy.newOrderChannelName,
        channelDescription: copy.newOrderChannelDescription,
      );
    } catch (e) {
      debugPrint('OrderWatcher: alert failed: $e');
    }
  }

  Future<void> _onEventRow(Map<String, dynamic> row) async {
    if (!_active || _disposed) return;
    final order = Order.fromMap(row);
    if (order == null) {
      // Schema drift from the web app (rename/new shape): loud, not silent.
      debugPrint('OrderWatcher: unparseable event row keys: ${row.keys}');
      return;
    }
    if (!_isFresh(order)) return;
    await _alert(order);
  }

  Future<void> _pollOnce({required bool notify}) async {
    if (!_active || _disposed) return;
    late final List<Order> orders;
    try {
      orders = await _fetchOrders();
    } catch (e) {
      debugPrint('OrderWatcher: poll fetch failed: $e');
      return;
    }
    if (!_active || _disposed) return;
    if (!notify) {
      _seen.addAll(orders.map((o) => o.id));
      await _persistSeen();
      return;
    }
    final fresh = orders.where(_isFresh).toList()
      ..sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = at.compareTo(bt);
        return cmp != 0 ? cmp : a.id.compareTo(b.id);
      });
    if (fresh.isEmpty) return;
    // Cap the flood (long outage): alert the most recent, oldest-first —
    // but mark everything seen so the cursor jumps past the backlog.
    final toAlert = fresh.length <= maxAlertsPerPoll
        ? fresh
        : fresh.sublist(fresh.length - maxAlertsPerPoll);
    _seen.addAll(fresh.map((o) => o.id));
    await _persistSeen();
    for (final order in toAlert) {
      if (!_active || _disposed) return;
      await _notify(order);
    }
  }

  /// Test helper: run one poll cycle with notifications enabled.
  @visibleForTesting
  Future<void> debugPollOnce() => _pollOnce(notify: true);

  /// Test helper: feed one event row as if Realtime delivered it.
  @visibleForTesting
  Future<void> debugEventRow(Map<String, dynamic> row) => _onEventRow(row);

  @visibleForTesting
  bool get debugActive => _active;

  Future<void> dispose() async {
    _disposed = true;
    await _deactivate();
    try {
      await _roleSub?.cancel();
    } catch (_) {}
    _roleSub = null;
    if (!_eventsDisposed) {
      _eventsDisposed = true;
      try {
        _events.dispose();
      } catch (_) {}
    }
  }

  /// Startup wiring: staff-gated subscription + poll. Never throws, never
  /// blocks — an unwired watcher simply means no alerts (reads unaffected).
  static OrderWatcher? _instance;

  static Future<void> wire() async {
    if (_instance != null) return;
    if (!SupabaseConfig.isConfigured) {
      debugPrint('OrderWatcher: Supabase not configured — alerts dormant.');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final watcher = OrderWatcher(
        events: SupabaseOrderEvents(),
        notifier: SystemOrderNotifier(),
        fetchOrders: OrdersRepo().getOrders,
        prefs: prefs,
      );
      _instance = watcher;
      final auth = AuthService.instance;
      await watcher.bind(auth.currentRoleStream, auth.currentRole);
      debugPrint('OrderWatcher: wired.');
    } catch (e) {
      debugPrint('OrderWatcher: wiring failed, alerts dormant: $e');
    }
  }

  /// Test / teardown helper. Safe to call when not wired.
  static Future<void> disposeWire() async {
    final watcher = _instance;
    _instance = null;
    try {
      await watcher?.dispose();
    } catch (_) {}
  }
}
