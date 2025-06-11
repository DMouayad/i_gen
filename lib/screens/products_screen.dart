import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/trina_table_header.dart';
import 'package:trina_grid/trina_grid.dart';

class ProductsScreen2 extends StatefulWidget {
  const ProductsScreen2({super.key, required this.unsavedProductCountNotifier});
  final ValueNotifier<int> unsavedProductCountNotifier;

  @override
  State<ProductsScreen2> createState() => _ProductsScreen2State();
}

class _ProductsScreen2State extends State<ProductsScreen2> {
  late final List<TrinaColumn> columns;
  final storedProducts = GetIt.I.get<ProductsController>().products;
  late TrinaGridStateManager stateManager;
  late final List<TrinaRow> rows;

  final ValueNotifier<String?> validationErrorNotifier = ValueNotifier(null);

  bool _disposed = false;

  final textStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
  @override
  void dispose() {
    _disposed = true;
    validationErrorNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    columns = [
      TrinaColumn(
        title: 'ID',
        field: 'id',
        type: TrinaColumnType.text(),
        validator: (value, validationContext) {
          for (final row in validationContext.stateManager.refRows) {
            if (row.cells['id']!.value == value &&
                row.cells['status']!.value == 'saved') {
              validationContext.row.cells['status']!.value = 'error';
              return 'A Product with model $value already exists';
            }
          }
          validationContext.row.cells['status']!.value = 'edited';
          stateManager.notifyListeners();
          return null;
        },
        sort: TrinaColumnSort.descending,
        enableEditingMode: true,
        renderer:
            (rendererContext) => Container(
              constraints: BoxConstraints.expand(),
              margin: EdgeInsets.all(.1),
              alignment: Alignment.center,
              color: switch (rendererContext.row.cells['status']!.value) {
                'edited' => Colors.amber[100]!,
                'error' => context.colorScheme.errorContainer,
                _ =>
                  rendererContext.rowIdx % 2 == 0
                      ? context.colorScheme.surface
                      : Colors.white,
              },
              child: Text(rendererContext.cell.value, style: textStyle),
            ),
        width: 50,
        cellPadding: EdgeInsets.zero,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableTitleChecked: false,
        textAlign: TrinaColumnTextAlign.center,
      ),
      TrinaColumn(
        title: 'Name',
        field: 'name',
        type: TrinaColumnType.text(),
        minWidth: 300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableEditingMode: true,
        enableTitleChecked: false,
      ),
      TrinaColumn(
        title: 'Actions',
        field: 'status',
        width: 70,
        type: TrinaColumnType.select(<String>[
          'saved',
          'edited',
          'created',
          'error',
        ]),
        enableEditingMode: false,
        enableContextMenu: false,
        enableColumnDrag: false,
        frozen: TrinaColumnFrozen.end,

        renderer: (rendererContext) {
          return OverflowBar(
            alignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Icon(Icons.delete),
                onPressed: () async {
                  final toDelete =
                      GetIt.I.get<ProductsController>().products[rendererContext
                          .row
                          .cells['id']!
                          .value];
                  // ONLY if the product exists in the db, delete it
                  if (toDelete != null) {
                    await GetIt.I.get<ProductsController>().deleteProduct(
                      toDelete,
                    );
                  }
                  stateManager.removeRows([rendererContext.row]);
                  updateDirtyCount();
                },
              ),
              if (rendererContext.cell.value == 'edited') ...[
                IconButton(
                  icon: Icon(Icons.done),
                  onPressed: () async {
                    await GetIt.I.get<ProductsController>().save(
                      model: rendererContext.row.cells['id']!.value,
                      name: rendererContext.row.cells['name']!.value,
                    );
                    rendererContext.row.cells['status']!.value = 'saved';

                    stateManager.commitChanges(
                      cell: rendererContext.row.cells['id']!,
                    );
                    stateManager.commitChanges(
                      cell: rendererContext.row.cells['name']!,
                    );
                    stateManager.setEditing(false);
                    updateDirtyCount();
                  },
                ),
                IconButton(
                  icon: Icon(Icons.undo),
                  onPressed: () {
                    stateManager.revertChanges(
                      cells: rendererContext.row.cells.values.toList(),
                    );
                    stateManager.setEditing(false);

                    updateDirtyCount();
                    rendererContext.cell.value = 'saved';
                  },
                ),
              ],
            ],
          );
        },
      ),
    ];

    rows =
        GetIt.I
            .get<ProductsController>()
            .products
            .values
            .map(
              (p) => TrinaRow(
                cells: {
                  'id': TrinaCell(value: p.model),
                  'name': TrinaCell(value: p.name),
                  'status': TrinaCell(value: 'saved'),
                },
              ),
            )
            .toList();

    super.initState();
  }

  void updateDirtyCount() {
    if (_disposed) return;

    // Use Future.microtask to ensure we're not updating during build or dispose
    Future.microtask(() {
      if (_disposed) return;

      int count = 0;
      for (var row in rows) {
        for (var cell in row.cells.values) {
          if (cell.isDirty) {
            count++;
          }
        }
      }
      if (!_disposed) {
        widget.unsavedProductCountNotifier.value = count;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1024,
      child: Column(
        children: [
          Flexible(
            child: Container(
              width: 1024,
              height: context.height,
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: TrinaGrid(
                columns: columns,
                rows: rows,
                onChanged: (TrinaGridOnChangedEvent event) {
                  updateDirtyCount();

                  if (event.row.cells['status']!.value == 'saved') {
                    event.row.cells['status']!.value = 'edited';
                    stateManager.notifyListeners();
                  }
                },

                onValidationFailed: (event) {
                  stateManager.gridFocusNode.unfocus();
                  stateManager.setSelecting(false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        event.errorMessage,
                        style: textStyle.copyWith(
                          color: context.colorScheme.onErrorContainer,
                        ),
                      ),

                      behavior: SnackBarBehavior.floating,
                      width: min(700, context.width * .8),
                      backgroundColor: context.colorScheme.errorContainer,
                      duration: Duration(seconds: 10),
                    ),
                  );

                  stateManager.setEditing(false);
                },
                createHeader:
                    (stateManager) => TrinaTableHeader(
                      addNewText: 'Add Product',
                      unSavedCountText:
                          (count) => 'You have $count un saved products',
                      unSavedCountNotifier: widget.unsavedProductCountNotifier,
                      stateManager: stateManager,
                      newRow:
                          () => TrinaRow(
                            cells: {
                              'id': TrinaCell(value: 'new'),
                              'name': TrinaCell(value: 'new'),
                              'status': TrinaCell(value: 'created'),
                            },
                          ),
                    ),

                configuration: TrinaGridConfiguration(
                  enterKeyAction: TrinaGridEnterKeyAction.editingAndMoveRight,
                  style: TrinaGridStyleConfig(
                    cellDirtyColor: Colors.amber[100]!,
                    borderColor: context.colorScheme.surfaceDim,
                    gridBorderColor: context.colorScheme.surfaceDim,
                    gridBorderRadius: BorderRadius.circular(6),
                    cellTextStyle: textStyle,
                    columnTextStyle: textStyle.copyWith(
                      color: context.colorScheme.primary,
                    ),
                    evenRowColor: Colors.white,
                    oddRowColor: context.colorScheme.surface,
                  ),
                  scrollbar: TrinaGridScrollbarConfig(showHorizontal: false),
                  columnSize: TrinaGridColumnSizeConfig(
                    autoSizeMode: TrinaAutoSizeMode.scale,
                  ),
                ),

                onLoaded: (TrinaGridOnLoadedEvent event) {
                  event.stateManager.setSelectingMode(
                    TrinaGridSelectingMode.cell,
                  );
                  stateManager = event.stateManager;
                  stateManager.setChangeTracking(true);
                  stateManager.setAutoEditing(true);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
