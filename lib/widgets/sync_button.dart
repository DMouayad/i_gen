import 'package:flutter/material.dart';

import 'package:i_gen/repos/sync_trigger.dart';
import 'package:i_gen/utils/context_extensions.dart';

/// The single sync surface for AppBars and table headers: a refresh button
/// that becomes a spinner while the engine reports `syncing`.
///
/// Fixed 48px box in both states (the IconButton constraint), so starting
/// or finishing a sync never shifts surrounding layout. Tapping mid-sync is
/// impossible — the button is replaced, not disabled — and [onSynced] runs
/// after the sync settles, success or failure, so callers just pass their
/// reload hook instead of hand-rolling `syncNow().then(...)`.
class SyncButton extends StatelessWidget {
  const SyncButton({super.key, this.onSynced, this.size = 16});

  /// Reload-after-sync hook (repo/controller refill). Optional: without it
  /// the button still triggers a sync (pushing pending edits).
  final Future<void> Function()? onSynced;

  /// Spinner diameter while syncing. Defaults to the old SyncSpinner look.
  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SyncUiState>(
      valueListenable: SyncTrigger.instance.state,
      builder: (context, state, _) {
        return SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: state.status == SyncStatus.syncing
                ? SizedBox(
                    width: size,
                    height: size,
                    child: const CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : IconButton(
                    tooltip: context.l10n.refresh,
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      await SyncTrigger.instance.syncNow();
                      await onSynced?.call();
                    },
                  ),
          ),
        );
      },
    );
  }
}
