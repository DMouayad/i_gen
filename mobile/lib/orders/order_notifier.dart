import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Tray-notification seam (Phase 11) so the watcher is unit-testable:
/// production uses [SystemOrderNotifier], tests use [FakeOrderNotifier].
abstract class OrderNotifier {
  /// Prepares the plugin (channel setup on Android). Safe to call twice;
  /// no-ops on platforms without tray support.
  Future<void> initialize();

  /// Triggers the OS permission prompt where required (Android 13+, iOS).
  /// Best-effort: denial only means silent alerts, never a crash.
  Future<void> requestPermission();

  /// Shows one new-order alert. Channel strings come from the caller (they
  /// are localized where the current locale is resolvable). The OS-level id
  /// derives from [orderId]: ids must be stable per order (a backlog fires
  /// several shows within one second — epoch-based ids overwrite each other
  /// and orders vanish from the tray). Never throws — presentation failures
  /// degrade to a log line so the watcher can never break sync or UI.
  Future<void> showNewOrder({
    required String orderId,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
  });
}

/// OS tray notifications via flutter_local_notifications. Mobile-only:
/// on desktop the plugin has no tray to post to, so every method is a
/// deliberate no-op there (the watcher poll still runs for future use).
class SystemOrderNotifier implements OrderNotifier {
  SystemOrderNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  @override
  Future<void> initialize() async {
    if (_initialized || !_supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('OrderNotifier: initialize failed: $e');
    }
  }

  @override
  Future<void> requestPermission() async {
    if (!_supported) return;
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      } else {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('OrderNotifier: permission request failed: $e');
    }
  }

  @override
  Future<void> showNewOrder({
    required String orderId,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
  }) async {
    if (!_supported) return;
    if (!_initialized) await initialize();
    try {
      await _plugin.show(
        id: orderId.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'new_orders',
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('OrderNotifier: show failed: $e');
    }
  }
}

/// Records alerts for tests.
class FakeOrderNotifier implements OrderNotifier {
  final shown =
      <
        ({
          String orderId,
          int id,
          String title,
          String body,
          String channelName,
          String channelDescription,
        })
      >[];
  int permissionRequests = 0;
  int initializations = 0;

  @override
  Future<void> initialize() async {
    initializations++;
  }

  @override
  Future<void> requestPermission() async {
    permissionRequests++;
  }

  @override
  Future<void> showNewOrder({
    required String orderId,
    required String title,
    required String body,
    required String channelName,
    required String channelDescription,
  }) async {
    shown.add((
      orderId: orderId,
      id: orderId.hashCode & 0x7fffffff,
      title: title,
      body: body,
      channelName: channelName,
      channelDescription: channelDescription,
    ));
  }
}
