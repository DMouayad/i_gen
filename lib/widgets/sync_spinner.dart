import 'package:flutter/material.dart';

import 'package:i_gen/repos/sync_trigger.dart';

/// Tiny sync-activity indicator for AppBars and table headers: a small
/// spinner while the engine reports `syncing`, a fixed-size gap otherwise
/// (no layout jump when sync starts/stops). Read-only: reflects
/// [SyncTrigger] state, never triggers a sync itself.
class SyncSpinner extends StatelessWidget {
  const SyncSpinner({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncUiState>(
      valueListenable: SyncTrigger.instance.state,
      builder: (context, state, _) {
        final syncing = state.status == SyncStatus.syncing;
        return SizedBox(
          width: size + 8,
          height: size + 8,
          child: Center(
            child: syncing
                ? SizedBox(
                    width: size,
                    height: size,
                    child: const CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
