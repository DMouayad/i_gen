import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/auth/supabase_config.dart';
import 'package:i_gen/repos/sync_trigger.dart';

import 'auth_info.dart';
import 'supabase_gateway.dart';
import 'sync_service.dart';

/// Staging gate (Phase 5 spec): the sync UI stays hidden until the checklist
/// (two-user RLS evidence, kill-mid-run tests, staging round-trip) passes.
/// Flip to `true` only then. The engine and outbox keep working regardless —
/// the flag gates visibility, never data.
const bool kSyncStagingGatePassed = false;

/// Adapts the Phase 1 auth module to the engine's identity contract.
class AuthServiceAdapter implements AuthInfoProvider {
  AuthServiceAdapter(this._auth);

  final AuthService _auth;

  @override
  String? get ownerId => _auth.cachedOwnerId;

  @override
  Stream<String?> get ownerIdStream =>
      _auth.currentUserStream.map((user) => user?.id);
}

/// Wires the sync engine at startup: gateway + service construction,
/// trigger registration, and automatic sync sources (connectivity regain,
/// app resume). All wiring is additive and never throws — an unwired engine
/// leaves changes safely queued in the outbox.
class SyncBootstrap {
  SyncBootstrap._();

  static WidgetsBindingObserver? _lifecycleObserver;
  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static StreamSubscription<String?>? _authSub;
  static Timer? _authDebounce;

  static Future<void> wire(Database db) async {
    if (!SupabaseConfig.isConfigured) {
      debugPrint('SyncBootstrap: Supabase not configured — sync dormant.');
      return;
    }
    try {
      final auth = AuthServiceAdapter(AuthService.instance);
      final remote = SupabaseGateway(Supabase.instance.client);
      // Always bind the fresh db handle: re-wire replaces a stale service
      // (tests open a new temp db per case; production wires once).
      if (GetIt.I.isRegistered<SyncService>()) {
        try {
          await GetIt.I.get<SyncService>().dispose();
        } catch (_) {}
        GetIt.I.unregister<SyncService>();
      }
      final service = SyncService(db: db, remote: remote, auth: auth);
      GetIt.I.registerSingleton<SyncService>(service);

      // `Future<SyncResult>` is assignable to the `Future<void>` slot.
      SyncTrigger.instance.onSyncRequested = service.syncNow;

      // Phase A: auto-sync on sign-in. Debounced to coalesce rapid flaps;
      // relies on SyncService.syncNow() inflight coalescing so no parallel
      // sync loops are created. Sign-out cancels pending debounce and does
      // nothing else. Subscription errors are swallowed so wiring never throws.
      try {
        await _authSub?.cancel();
        _authSub = null;
        _authDebounce?.cancel();
        _authSub = auth.ownerIdStream.listen(
          (id) {
            if (id != null) {
              _authDebounce?.cancel();
              _authDebounce = Timer(const Duration(milliseconds: 500), () {
                // Coalesces via SyncService._inflight; never creates parallel loops.
                unawaited(
                  service.syncNow().then<void>(
                    (_) {},
                    onError: (Object e) {
                      debugPrint(
                        'SyncBootstrap: auto-sync on sign-in failed: $e',
                      );
                    },
                  ),
                );
              });
            } else {
              _authDebounce?.cancel();
              _authDebounce = null;
            }
          },
          onError: (Object e) {
            debugPrint('SyncBootstrap: auth stream error: $e');
          },
          cancelOnError: false,
        );
      } catch (e) {
        debugPrint('SyncBootstrap: auth subscription failed: $e');
      }

      try {
        await _connectivitySub?.cancel();
      } catch (_) {}
      _connectivitySub = null;
      // onError is required: on Windows the platform stream can fail with
      // NetworkManager::StartListen (upstream connectivity_plus bug #3713).
      // Without it the auto-sync trigger dies silently on those machines;
      // reconnect-pull still happens on app resume below.
      _connectivitySub = Connectivity().onConnectivityChanged.listen(
        (results) {
          if (!results.contains(ConnectivityResult.none)) {
            unawaited(service.handleConnectivityRegained());
          }
        },
        onError: (Object e) {
          debugPrint('SyncBootstrap: connectivity stream failed: $e');
        },
        cancelOnError: false,
      );

      if (_lifecycleObserver != null) {
        WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      }
      _lifecycleObserver = _SyncResumeObserver(service);
      WidgetsBinding.instance.addObserver(_lifecycleObserver!);

      debugPrint('SyncBootstrap: engine wired.');
    } catch (e) {
      debugPrint('SyncBootstrap: wiring failed, sync dormant: $e');
    }
  }

  /// Test / teardown helper: cancels auth + connectivity subscriptions,
  /// debounce timer, lifecycle observer, and the registered service.
  /// Safe to call multiple times or when not wired.
  static Future<void> dispose() async {
    _authDebounce?.cancel();
    _authDebounce = null;
    try {
      await _authSub?.cancel();
    } catch (_) {}
    _authSub = null;
    try {
      await _connectivitySub?.cancel();
    } catch (_) {}
    _connectivitySub = null;
    if (_lifecycleObserver != null) {
      try {
        WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      } catch (_) {}
      _lifecycleObserver = null;
    }
    SyncTrigger.instance.onSyncRequested = null;
    if (GetIt.I.isRegistered<SyncService>()) {
      try {
        await GetIt.I.get<SyncService>().dispose();
      } catch (_) {}
      GetIt.I.unregister<SyncService>();
    }
  }
}

class _SyncResumeObserver extends WidgetsBindingObserver {
  _SyncResumeObserver(this._service);

  final SyncService _service;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.handleAppResumed());
    }
  }
}
