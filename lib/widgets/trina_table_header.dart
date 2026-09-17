import 'package:flutter/material.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/sync_button.dart';
import 'package:trina_grid/trina_grid.dart';

class TrinaTableHeader extends StatelessWidget {
  const TrinaTableHeader({
    required this.unSavedCountNotifier,
    super.key,
    required this.stateManager,
    required this.newRow,
    required this.addNewText,
    required this.unSavedCountText,
    this.showAdd = true,
    this.onRefresh,
  });
  final String addNewText;
  final String Function(int) unSavedCountText;
  final ValueNotifier<int> unSavedCountNotifier;
  final TrinaGridStateManager stateManager;
  final TrinaRow Function() newRow;

  /// When false the add button is hidden (role read-only). Defaults to true
  /// so existing callers keep today's behavior.
  final bool showAdd;

  /// Post-sync reload hook (grid refill). The button always shows — syncing
  /// matters most for read-only roles that cannot have unsaved edits.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppGaps.sm,
        horizontal: AppGaps.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ValueListenableBuilder(
            valueListenable: unSavedCountNotifier,
            builder: (context, count, child) {
              return count > 0
                  ? Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppGaps.xs,
                              ),
                              child: Icon(
                                Icons.warning_amber,
                                color: context.colorScheme.tertiary,
                              ),
                            ),
                          ),
                          TextSpan(
                            text: unSavedCountText(count),
                            style: context.textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    )
                  : SizedBox.shrink();
            },
          ),
          if (showAdd) ...[
            const SizedBox(width: AppGaps.md),
            DecoratedBox(
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(color: context.colorScheme.outline),
                ),
              ),
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                label: Text(addNewText, style: context.textTheme.titleMedium),
                icon: Icon(Icons.add),
                onPressed: () {
                  stateManager.insertRows(
                    stateManager.refRows.last.sortIdx + 1,
                    [newRow()],
                  );
                  final newLastRow = stateManager.refRows.last;
                  stateManager.moveScrollByRow(
                    TrinaMoveDirection.down,
                    newLastRow.sortIdx,
                  );

                  stateManager.setHoveredRowIdx(newLastRow.sortIdx);
                },
              ),
            ),
          ],
          const Spacer(),
          SyncButton(onSynced: onRefresh),
        ],
      ),
    );
  }
}
