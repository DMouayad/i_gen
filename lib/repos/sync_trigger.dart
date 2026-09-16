import 'dart:async';

import 'package:flutter/foundation.dart';

/// Sync health as shown in settings (Phase 4 user stories 3-5).
enum SyncStatus {
  /// Everything acknowledged; outbox empty.
  synced,

  /// A sync run is in flight.
  syncing,

  /// Local changes are queued but no engine state is known yet
  /// (engine not wired, or no run since the last write).
  pending,

  /// A parked op error or failed run needs attention.
  error,

  /// Initial state before any local stats have been read.
  unknown,
}

/// Snapshot of sync health. The engine (Phase 3) pushes authoritative
/// states via [SyncTrigger.report]; until then the settings UI derives an
/// honest state from local outbox stats.
class SyncUiState {
  final SyncStatus status;
  final DateTime? lastSyncAt;
  final String? lastError;

  /// Engine-reported per-table counters from the last run, when available.
  final Map<String, int> uploadedByTable;
  final Map<String, int> downloadedByTable;

  /// Rows pulled but not merged (orphan children waiting on parents,
  /// stale LWW losers) per table, from the last run. Visible instead of
  /// `debugPrint`-only so silent starvation (e.g. prices never arriving)
  /// is diagnosable from settings.
  final Map<String, int> skippedByTable;

  const SyncUiState({
    this.status = SyncStatus.unknown,
    this.lastSyncAt,
    this.lastError,
    this.uploadedByTable = const {},
    this.downloadedByTable = const {},
    this.skippedByTable = const {},
  });

  SyncUiState copyWith({
    SyncStatus? status,
    DateTime? lastSyncAt,
    String? lastError,
    bool clearError = false,
    Map<String, int>? uploadedByTable,
    Map<String, int>? downloadedByTable,
    Map<String, int>? skippedByTable,
  }) {
    return SyncUiState(
      status: status ?? this.status,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: clearError ? null : (lastError ?? this.lastError),
      uploadedByTable: uploadedByTable ?? this.uploadedByTable,
      downloadedByTable: downloadedByTable ?? this.downloadedByTable,
      skippedByTable: skippedByTable ?? this.skippedByTable,
    );
  }
}

/// Session counters for sync health (Phase 5 observability).
///
/// Owned by [SyncTrigger] so settings reads one instance instead of static
/// globals; reset only by tests.
class SyncCounters {
  int parkedEvictions = 0;
  int payloadWarnings = 0;

  void registerParkedEvictions(int count) => parkedEvictions += count;
  void registerPayloadWarning() => payloadWarnings++;

  @visibleForTesting
  void resetForTests() {
    parkedEvictions = 0;
    payloadWarnings = 0;
  }
}

///
/// One-direction seam between repositories/UI and the sync engine:
///
/// * Repositories call [poke] after every mutation (debounced ~2s).
/// * The settings "Sync now" button calls [syncNow].
/// * The engine (Phase 3, built in parallel) registers its public
///   `syncNow()` as [onSyncRequested] and pushes states via [report].
///
/// Repositories and widgets import only this file — never `lib/sync/*`.
class SyncTrigger {
  SyncTrigger._internal();

  static final SyncTrigger instance = SyncTrigger._internal();

  /// Session sync-health counters (evictions, payload warnings).
  final SyncCounters counters = SyncCounters();

  /// Set by the sync engine at startup: `SyncTrigger.instance
  /// .onSyncRequested = syncService.syncNow;`
  Future<void> Function()? onSyncRequested;

  /// Observable sync state for the settings UI.
  final ValueNotifier<SyncUiState> state = ValueNotifier(const SyncUiState());

  static const Duration debounce = Duration(seconds: 2);

  Timer? _debounce;
  bool _running = false;

  /// Called by repositories after each mutation. Fire-and-forget by
  /// design: never throws, never blocks the write.
  void poke() {
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      // Swallow errors here: a debounced auto-push must never surface an
      // unhandled async exception (e.g. engine not registered yet in tests
      // or before Phase 3 lands). The manual path still throws.
      syncNow().then((_) {}, onError: (_) {});
    });
  }

  /// Manual trigger for the settings "Sync now" button.
  ///
  /// Throws [StateError] when the engine has not registered yet, so the
  /// UI can explain that changes are queued safely instead of pretending
  /// a sync happened.
  Future<void> syncNow() async {
    final requested = onSyncRequested;
    if (requested == null) {
      throw StateError(
        'Sync engine is not wired yet; changes remain queued in the outbox.',
      );
    }
    if (_running) return;
    _running = true;
    state.value = state.value.copyWith(status: SyncStatus.syncing);
    try {
      await requested();
      // The engine publishes the authoritative state via report() during the
      // run; only mark synced here if it didn't (e.g. a non-engine trigger).
      // Overwriting unconditionally would clobber a just-reported error.
      if (state.value.status == SyncStatus.syncing) {
        state.value = state.value.copyWith(
          status: SyncStatus.synced,
          lastSyncAt: DateTime.now(),
        );
      }
    } catch (e) {
      state.value = state.value.copyWith(
        status: SyncStatus.error,
        lastError: e.toString(),
      );
      rethrow;
    } finally {
      _running = false;
    }
  }

  /// Called by the engine to publish authoritative states
  /// (per-table up/down counters, parked errors, checkpoints).
  void report(SyncUiState next) => state.value = next;

  @visibleForTesting
  void resetForTests() {
    _debounce?.cancel();
    _debounce = null;
    _running = false;
    onSyncRequested = null;
    counters.resetForTests();
    state.value = const SyncUiState();
  }
}
