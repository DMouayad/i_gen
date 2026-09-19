import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/l10n/app_localizations_en.dart';
import 'package:i_gen/models/order.dart';
import 'package:i_gen/orders/order_events.dart';
import 'package:i_gen/orders/order_notifier.dart';
import 'package:i_gen/orders/order_watcher.dart';

Map<String, dynamic> orderRow(
  String id, {
  String status = 'pending',
  double total = 100,
  String currency = 'USD',
  String? createdAt,
}) => {
  'id': id,
  'customer_id': 'cust-1',
  'status': status,
  'total': total,
  'currency': currency,
  'created_at': createdAt ?? DateTime.utc(2026, 1, 1).toIso8601String(),
};

Order orderOf(Map<String, dynamic> row) => Order.fromMap(row)!;

class _Harness {
  _Harness._();

  static Future<_Harness> create({
    UserRole? initialRole = UserRole.admin,
    List<Map<String, dynamic>> server = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final events = FakeOrderEvents();
    final notifier = FakeOrderNotifier();
    var serverRows = List<Map<String, dynamic>>.from(server);
    final roles = StreamController<UserRole?>();
    final watcher = OrderWatcher(
      events: events,
      notifier: notifier,
      fetchOrders: () async => serverRows.map(orderOf).toList(),
      prefs: prefs,
      copyLoader: () async => AppLocalizationsEn(),
      pollInterval: const Duration(seconds: 60),
    );
    await watcher.bind(roles.stream, initialRole);
    // Flush the async activate path (permission, baseline, subscribe).
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final h = _Harness._();
    h.watcher = watcher;
    h.events = events;
    h.notifier = notifier;
    h.prefs = prefs;
    h.roles = roles;
    h.setServer = (rows) => serverRows = rows;
    return h;
  }

  late final OrderWatcher watcher;
  late final FakeOrderEvents events;
  late final FakeOrderNotifier notifier;
  late final SharedPreferences prefs;
  late final StreamController<UserRole?> roles;
  late void Function(List<Map<String, dynamic>> rows) setServer;

  Future<void> dispose() async {
    await watcher.dispose();
    await roles.close();
  }
}

void main() {
  test('staff login subscribes and baselines silently (no flood)', () async {
    final h = await _Harness.create(server: [orderRow('o1'), orderRow('o2')]);
    expect(h.watcher.debugActive, isTrue);
    expect(h.events.subscribes, 1);
    expect(h.notifier.permissionRequests, 1);
    expect(h.notifier.shown, isEmpty);

    await h.watcher.debugPollOnce();
    expect(h.notifier.shown, isEmpty);
    await h.dispose();
  });

  test(
    'realtime pending insert notifies once; poll does not re-notify',
    () async {
      final h = await _Harness.create(server: [orderRow('o1')]);
      h.events.emit(orderRow('o2', total: 250));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(h.notifier.shown, hasLength(1));
      expect(h.notifier.shown.single.title, 'New order');
      expect(h.notifier.shown.single.body, contains('250'));

      await h.watcher.debugPollOnce();
      expect(h.notifier.shown, hasLength(1));
      await h.dispose();
    },
  );

  test('non-pending inserts stay silent', () async {
    final h = await _Harness.create();
    h.events.emit(orderRow('o1', status: 'completed'));
    h.events.emit(orderRow('o2', status: 'cancelled'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.notifier.shown, isEmpty);

    h.setServer([
      orderRow('o1', status: 'completed'),
      orderRow('o2', status: 'completed'),
    ]);
    await h.watcher.debugPollOnce();
    expect(h.notifier.shown, isEmpty);
    await h.dispose();
  });

  test('restart with persisted cursor notifies only newer orders', () async {
    final h = await _Harness.create(server: [orderRow('o1')]);
    h.events.emit(orderRow('o2'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.notifier.shown, hasLength(1));

    // "Restart": same prefs, fresh watcher + fakes.
    final prefs = h.prefs;
    await h.dispose();
    final events2 = FakeOrderEvents();
    final notifier2 = FakeOrderNotifier();
    final watcher2 = OrderWatcher(
      events: events2,
      notifier: notifier2,
      fetchOrders: () async => [
        orderRow('o1'),
        orderRow('o2'),
        orderRow('o3'),
      ].map(orderOf).toList(),
      prefs: prefs,
      copyLoader: () async => AppLocalizationsEn(),
    );
    await watcher2.bind(const Stream.empty(), UserRole.admin);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(notifier2.shown, isEmpty);

    await watcher2.debugPollOnce();
    expect(notifier2.shown, isEmpty);
    await watcher2.dispose();
    events2.dispose();
  });

  test('logout unsubscribes and stops; customer never subscribes', () async {
    final h = await _Harness.create();
    expect(h.watcher.debugActive, isTrue);

    h.roles.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.watcher.debugActive, isFalse);
    expect(h.events.unsubscribes, 1);

    // Customer login: stays dormant, no permission prompt.
    final prompts = h.notifier.permissionRequests;
    h.roles.add(UserRole.customer);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.watcher.debugActive, isFalse);
    expect(h.events.subscribes, 1);
    expect(h.notifier.permissionRequests, prompts);

    // Events arriving while dormant are ignored.
    h.events.emit(orderRow('o9'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.notifier.shown, isEmpty);
    await h.dispose();
  });

  test('signed out from the start: fully dormant', () async {
    final h = await _Harness.create(initialRole: null);
    expect(h.watcher.debugActive, isFalse);
    expect(h.events.subscribes, 0);
    expect(h.notifier.permissionRequests, 0);
    await h.dispose();
  });

  test('backlog flood is capped but the cursor jumps past all', () async {
    final h = await _Harness.create();
    h.setServer([
      for (var i = 1; i <= 8; i++)
        orderRow(
          'o$i',
          total: 100.0 * i,
          createdAt: DateTime.utc(2026, 1, i).toIso8601String(),
        ),
    ]);
    await h.watcher.debugPollOnce();
    // Most recent five (o4..o8), oldest-first.
    expect(h.notifier.shown.map((s) => s.body).toList(), [
      '400.0 USD',
      '500.0 USD',
      '600.0 USD',
      '700.0 USD',
      '800.0 USD',
    ]);

    // Cursor jumped past the whole backlog: next poll is quiet.
    await h.watcher.debugPollOnce();
    expect(h.notifier.shown, hasLength(5));
    await h.dispose();
  });

  test('backlog alerts carry distinct OS ids (no tray overwrite)', () async {
    final h = await _Harness.create();
    h.setServer([
      for (var i = 1; i <= 3; i++)
        orderRow(
          'o$i',
          total: 100.0 * i,
          createdAt: DateTime.utc(2026, 1, i).toIso8601String(),
        ),
    ]);
    await h.watcher.debugPollOnce();
    final ids = h.notifier.shown.map((s) => s.id).toSet();
    expect(ids, hasLength(3));
    expect(h.notifier.shown.map((s) => s.orderId).toSet(), {'o1', 'o2', 'o3'});
    await h.dispose();
  });

  test('rapid staff-logout-staff flap ends active, no leaked timer', () async {
    final h = await _Harness.create();
    h.roles.add(null);
    h.roles.add(UserRole.employee);
    h.roles.add(null);
    h.roles.add(UserRole.admin);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(h.watcher.debugActive, isTrue);
    // Fully functional: a fresh order still alerts exactly once...
    h.setServer([orderRow('o1'), orderRow('o2')]);
    h.events.emit(orderRow('o3'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.notifier.shown.where((s) => s.orderId == 'o3'), hasLength(1));
    // ...and one poll cycle produces no duplicates (single live timer).
    await h.watcher.debugPollOnce();
    expect(h.notifier.shown.where((s) => s.orderId == 'o3'), hasLength(1));
    await h.dispose();
  });

  test(
    'copy loader failure never crashes; order stays seen (at-most-once)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final events = FakeOrderEvents();
      final notifier = FakeOrderNotifier();
      final roles = StreamController<UserRole?>();
      final watcher = OrderWatcher(
        events: events,
        notifier: notifier,
        fetchOrders: () async => [orderOf(orderRow('o1'))],
        prefs: prefs,
        copyLoader: () => throw StateError('no copy'),
      );
      await watcher.bind(roles.stream, UserRole.admin);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      events.emit(orderRow('o2'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(notifier.shown, isEmpty);

      // Seen persisted despite the failure: no re-alert loop on next poll.
      await watcher.debugPollOnce();
      expect(notifier.shown, isEmpty);
      await watcher.dispose();
      await roles.close();
    },
  );
}
