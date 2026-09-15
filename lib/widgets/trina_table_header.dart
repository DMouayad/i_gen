import 'package:flutter/material.dart';
import 'package:i_gen/utils/context_extensions.dart';
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
  });
  final String addNewText;
  final String Function(int) unSavedCountText;
  final ValueNotifier<int> unSavedCountNotifier;
  final TrinaGridStateManager stateManager;
  final TrinaRow Function() newRow;

  /// When false the add button is hidden (role read-only). Defaults to true
  /// so existing callers keep today's behavior.
  final bool showAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 7, horizontal: 14),
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
                                horizontal: 4.0,
                              ),
                              child: Icon(
                                Icons.warning_amber,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                          TextSpan(
                            text: unSavedCountText(count),
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : SizedBox.shrink();
            },
          ),
          if (showAdd)
            TextButton.icon(
              label: Text(addNewText, style: context.textTheme.titleMedium),
              icon: Icon(Icons.add),
              onPressed: () {
                stateManager.insertRows(stateManager.refRows.last.sortIdx + 1, [
                  newRow(),
                ]);
                final newLastRow = stateManager.refRows.last;
                stateManager.moveScrollByRow(
                  TrinaMoveDirection.down,
                  newLastRow.sortIdx,
                );

                stateManager.setHoveredRowIdx(newLastRow.sortIdx);
              },
            ),
        ],
      ),
    );
  }
}
