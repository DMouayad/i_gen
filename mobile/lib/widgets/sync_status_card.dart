import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/repos/sync_maintenance.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:sqflite/sqflite.dart';

/// Settings sync surface (Phase 4 user stories 3-5, Phase 5 observability):
/// status indicator (synced / syncing / error), last-sync time,
/// "Sync now" trigger, parked-error line, and local counters.
///
/// Works before the Phase 3 engine lands: states are derived from local
/// outbox stats and the button explains that changes are queued safely.
class SyncStatusCard extends StatefulWidget {
  const SyncStatusCard({super.key});

  @override
  State<SyncStatusCard> createState() => _SyncStatusCardState();
}

class _SyncStatusCardState extends State<SyncStatusCard> {
  Future<SyncStats>? _statsFuture;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    if (!GetIt.I.isRegistered<Database>()) return;
    _statsFuture = SyncMaintenance.readStats(GetIt.I.get<Database>());
  }

  Future<void> _onSyncNow() async {
    setState(() => _syncing = true);
    try {
      await SyncTrigger.instance.syncNow();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.syncCompleted)));
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.syncFailed(e.toString()))),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _refresh();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!GetIt.I.isRegistered<Database>()) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(
            color: context.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: ListTile(
          leading: const Icon(Icons.cloud_off_outlined),
          title: Text(context.l10n.syncUnavailable),
        ),
      );
    }
    return ValueListenableBuilder<SyncUiState>(
      valueListenable: SyncTrigger.instance.state,
      builder: (context, engineState, _) {
        return FutureBuilder<SyncStats>(
          future: _statsFuture,
          builder: (context, snapshot) {
            final stats = snapshot.data ?? const SyncStats();
            final resolved = _resolve(context, engineState, stats);
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.card),
                side: BorderSide(
                  color: context.colorScheme.outlineVariant.withValues(
                    alpha: 0.5,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppGaps.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            key: ValueKey(resolved.status),
                            width: AppGaps.md,
                            height: AppGaps.md,
                            decoration: BoxDecoration(
                              color: resolved.dotColor(context),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppGaps.sm),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              resolved.label,
                              key: ValueKey(resolved.label),
                              style: context.textTheme.titleMedium,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: const ButtonStyle(
                            minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                          ),
                          onPressed: _syncing ? null : _onSyncNow,
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: _syncing
                                ? const SizedBox(
                                    key: ValueKey('syncing'),
                                    width: AppGaps.md,
                                    height: AppGaps.md,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.sync_outlined,
                                    key: ValueKey('idle'),
                                  ),
                          ),
                          label: Text(context.l10n.syncNow),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppGaps.xs),
                    Text(
                      context.l10n.lastSyncLabel(
                        _formatTime(context, resolved.lastSyncAt),
                      ),
                      style: context.textTheme.bodyMedium,
                    ),
                    Text(
                      context.l10n.queuedChanges(
                        stats.pendingTotal,
                        stats.pendingByTable.isEmpty
                            ? ''
                            : ' (${_formatCounters(stats.pendingByTable)})',
                      ),
                      style: context.textTheme.bodyMedium,
                    ),
                    if (engineState.downloadedByTable.isNotEmpty)
                      Text(
                        context.l10n.lastDownloadLabel(
                          _formatCounters(engineState.downloadedByTable),
                        ),
                        style: context.textTheme.bodyMedium,
                      ),
                    if (engineState.skippedByTable.isNotEmpty)
                      Text(
                        context.l10n.skippedRowsLabel(
                          _formatCounters(engineState.skippedByTable),
                        ),
                        // Warning, not error: held rows are routine-transient
                        // (orphans waiting on parents), not failures.
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.tertiary,
                        ),
                      ),
                    if (resolved.errorLine != null) ...[
                      const SizedBox(height: AppGaps.sm),
                      Text(
                        context.l10n.syncNeedsAttentionDetail(
                          resolved.errorLine!,
                        ),
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.error,
                        ),
                      ),
                    ],
                    if (stats.parkedEvictions > 0)
                      Text(
                        context.l10n.parkedEvictedWarning(
                          stats.parkedEvictions,
                        ),
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  _Resolved _resolve(
    BuildContext context,
    SyncUiState engine,
    SyncStats stats,
  ) {
    final lastSync = engine.lastSyncAt ?? stats.lastSyncAt;
    final parkedError = engine.lastError ?? stats.firstParkedError;
    switch (engine.status) {
      case SyncStatus.syncing:
        return _Resolved(
          status: SyncStatus.syncing,
          label: context.l10n.syncingStatus,
          lastSyncAt: lastSync,
          errorLine: null,
        );
      case SyncStatus.error:
        return _Resolved(
          status: SyncStatus.error,
          label: context.l10n.syncErrorStatus,
          lastSyncAt: lastSync,
          errorLine: parkedError ?? context.l10n.unknownError,
        );
      case SyncStatus.synced:
        return _Resolved(
          status: SyncStatus.synced,
          label: stats.pendingTotal == 0
              ? context.l10n.syncedStatus
              : context.l10n.syncedWithPending(stats.pendingTotal),
          lastSyncAt: lastSync,
          errorLine: parkedError,
        );
      case SyncStatus.pending:
      case SyncStatus.unknown:
        if (parkedError != null) {
          return _Resolved(
            status: SyncStatus.error,
            label: context.l10n.syncNeedsAttention,
            lastSyncAt: lastSync,
            errorLine: parkedError,
          );
        }
        if (stats.pendingTotal > 0) {
          return _Resolved(
            status: SyncStatus.pending,
            label: context.l10n.waitingToSync(stats.pendingTotal),
            lastSyncAt: lastSync,
            errorLine: null,
          );
        }
        return _Resolved(
          status: SyncStatus.synced,
          label: context.l10n.upToDateStatus,
          lastSyncAt: lastSync,
          errorLine: null,
        );
    }
  }

  String _formatTime(BuildContext context, DateTime? t) {
    if (t == null) return context.l10n.neverSynced;
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  String _formatCounters(Map<String, int> counters) {
    return counters.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }
}

class _Resolved {
  final SyncStatus status;
  final String label;
  final DateTime? lastSyncAt;
  final String? errorLine;

  _Resolved({
    required this.status,
    required this.label,
    required this.lastSyncAt,
    required this.errorLine,
  });

  /// Single status → color map (one place, shared by dot and any future
  /// status-driven styling — no second switch on [SyncStatus]).
  Color dotColor(BuildContext context) => switch (status) {
    SyncStatus.synced => context.colorScheme.primary,
    SyncStatus.syncing => context.colorScheme.secondary,
    SyncStatus.pending => context.colorScheme.tertiary,
    SyncStatus.error => context.colorScheme.error,
    SyncStatus.unknown => context.colorScheme.outline,
  };
}
