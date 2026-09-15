import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/repos/sync_maintenance.dart';
import 'package:i_gen/repos/sync_trigger.dart';
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
        ).showSnackBar(const SnackBar(content: Text('Sync completed.')));
      }
    } on StateError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
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
      return const Card(
        child: ListTile(
          leading: Icon(Icons.cloud_off),
          title: Text('Sync unavailable'),
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
            final resolved = _resolve(engineState, stats);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: resolved.dotColor(context),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            resolved.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _syncing ? null : _onSyncNow,
                          icon: _syncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: const Text('Sync now'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Last sync: ${_formatTime(resolved.lastSyncAt)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      'Queued changes: ${stats.pendingTotal}'
                      '${stats.pendingByTable.isEmpty ? '' : ' (${_formatCounters(stats.pendingByTable)})'}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (engineState.downloadedByTable.isNotEmpty)
                      Text(
                        'Last download: ${_formatCounters(engineState.downloadedByTable)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    if (resolved.errorLine != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Sync needs attention:\n${resolved.errorLine}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (stats.parkedEvictions > 0)
                      Text(
                        'Warning: ${stats.parkedEvictions} parked op(s) evicted this session (cap reached).',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
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

  _Resolved _resolve(SyncUiState engine, SyncStats stats) {
    final lastSync = engine.lastSyncAt ?? stats.lastSyncAt;
    final parkedError = engine.lastError ?? stats.firstParkedError;
    switch (engine.status) {
      case SyncStatus.syncing:
        return _Resolved(
          status: SyncStatus.syncing,
          label: 'Syncing…',
          lastSyncAt: lastSync,
          errorLine: null,
        );
      case SyncStatus.error:
        return _Resolved(
          status: SyncStatus.error,
          label: 'Sync error',
          lastSyncAt: lastSync,
          errorLine: parkedError ?? 'Unknown error.',
        );
      case SyncStatus.synced:
        return _Resolved(
          status: SyncStatus.synced,
          label: stats.pendingTotal == 0
              ? 'Synced'
              : 'Synced • ${stats.pendingTotal} change(s) queued',
          lastSyncAt: lastSync,
          errorLine: parkedError,
        );
      case SyncStatus.pending:
      case SyncStatus.unknown:
        if (parkedError != null) {
          return _Resolved(
            status: SyncStatus.error,
            label: 'Sync needs attention',
            lastSyncAt: lastSync,
            errorLine: parkedError,
          );
        }
        if (stats.pendingTotal > 0) {
          return _Resolved(
            status: SyncStatus.pending,
            label: 'Waiting to sync • ${stats.pendingTotal} change(s) queued',
            lastSyncAt: lastSync,
            errorLine: null,
          );
        }
        return _Resolved(
          status: SyncStatus.synced,
          label: 'Up to date',
          lastSyncAt: lastSync,
          errorLine: null,
        );
    }
  }

  String _formatTime(DateTime? t) {
    if (t == null) return 'Never';
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
    SyncStatus.synced => Colors.green,
    SyncStatus.syncing => Colors.blue,
    SyncStatus.pending => Colors.orange,
    SyncStatus.error => Theme.of(context).colorScheme.error,
    SyncStatus.unknown => Colors.grey,
  };
}
