import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/sync/sync_orchestrator.dart';

class QuickSyncButton extends StatelessWidget {
  const QuickSyncButton({super.key});

  @override
  Widget build(BuildContext context) {
    final orchestrator = GetIt.I.get<SyncOrchestrator>();
    final hasDefaultDevice = orchestrator.preferences.defaultDevice != null;

    if (!hasDefaultDevice) return const SizedBox.shrink();

    return StreamBuilder<AutoSyncState>(
      stream: orchestrator.stateStream,
      initialData: orchestrator.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? AutoSyncState.idle();
        final isActive =
            state.status != AutoSyncStatus.idle &&
            state.status != AutoSyncStatus.completed &&
            state.status != AutoSyncStatus.failed;

        return TextButton.icon(
          onPressed: isActive ? null : () => _onPressed(context, orchestrator),
          icon: isActive
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: Text(isActive ? 'Syncing...' : 'Quick Sync'),
        );
      },
    );
  }

  void _onPressed(BuildContext context, SyncOrchestrator orchestrator) async {
    final result = await orchestrator.syncWithDefaultDevice();

    if (!context.mounted) return;

    if (result.status == AutoSyncStatus.completed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sync complete! '
            '+${result.totalInserted} inserted, '
            '${result.totalUpdated} updated',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else if (result.status == AutoSyncStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: ${result.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
