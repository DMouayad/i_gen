import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/size_multi_select.dart';
import 'package:i_gen/widgets/trina_table_header.dart';
import 'package:trina_grid/trina_grid.dart';

class ProductsScreen2 extends StatefulWidget {
  const ProductsScreen2({super.key, required this.unsavedProductCountNotifier});
  final ValueNotifier<int> unsavedProductCountNotifier;

  @override
  State<ProductsScreen2> createState() => _ProductsScreen2State();
}

class _ProductsScreen2State extends State<ProductsScreen2> {
  final storedProducts = GetIt.I.get<ProductsController>().products;
  late TrinaGridStateManager stateManager;
  late List<TrinaRow> rows;

  /// Bumped on manual refresh to remount the grid with fresh rows.
  int _gridTick = 0;

  final ValueNotifier<String?> validationErrorNotifier = ValueNotifier(null);

  bool _disposed = false;

  TextStyle _cellTextStyle(BuildContext context) =>
      context.textTheme.bodyLarge!.copyWith(
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle _columnTextStyle(BuildContext context) =>
      _cellTextStyle(context).copyWith(color: context.colorScheme.primary);
  @override
  void dispose() {
    _disposed = true;
    validationErrorNotifier.dispose();
    super.dispose();
  }

  /// Whether catalog editing is disabled for the current role. Updated on
  /// every build from the auth stream; the database remains the enforcer.
  bool _readOnly = false;

  /// Builds the grid columns for the given mode. Called on every build so a
  /// role change (sign in/out) immediately flips edit affordances without
  /// touching the rows.
  List<TrinaColumn> _buildColumns(BuildContext context, bool readOnly) {
    return [
      TrinaColumn(
        title: context.l10n.productIdColumn,
        field: 'id',
        type: TrinaColumnType.text(),
        validator: (value, validationContext) {
          for (final row in validationContext.stateManager.refRows) {
            if (row.cells['id']!.value == value &&
                row.cells['status']!.value == 'saved') {
              validationContext.row.cells['status']!.value = 'error';
              return context.l10n.productAlreadyExists('$value');
            }
          }
          validationContext.row.cells['status']!.value = 'edited';
          stateManager.notifyListeners();
          return null;
        },
        sort: TrinaColumnSort.descending,
        enableEditingMode: !readOnly,
        renderer: (rendererContext) => Container(
          constraints: BoxConstraints.expand(),
          margin: EdgeInsets.all(.1),
          alignment: Alignment.center,
          color: switch (rendererContext.row.cells['status']!.value) {
            'edited' => AppColors.dirtyCell,
            'error' => context.colorScheme.errorContainer,
            _ => null,
          },
          child: Text(
            rendererContext.cell.value,
            style: _cellTextStyle(context),
          ),
        ),
        width: 50,
        cellPadding: EdgeInsets.zero,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableTitleChecked: false,
        textAlign: TrinaColumnTextAlign.center,
      ),
      TrinaColumn(
        title: context.l10n.productNameColumn,
        field: 'name',
        type: TrinaColumnType.text(),
        renderer: (rendererContext) =>
            Text(rendererContext.cell.value, style: _cellTextStyle(context)),
        minWidth: 300,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableEditingMode: !readOnly,
        enableTitleChecked: false,
      ),
      TrinaColumn(
        title: context.l10n.sizesColumn,
        field: 'sizes',
        type: TrinaColumnType.text(),
        // No inline editor: tapping opens the multi-select dialog, which
        // writes back through changeCellValue (dirty tracking intact).
        enableEditingMode: false,

        renderer: (rendererContext) => InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: readOnly
              ? null
              : () async {
                  final model =
                      rendererContext.row.cells['id']!.value as String? ?? '';
                  final product = GetIt.I
                      .get<ProductsController>()
                      .products[model];
                  final picked = await showSizeMultiSelect(
                    context,
                    initial: Product.parseSizeList(
                      rendererContext.cell.value as String? ?? '',
                    ),
                    title: product == null
                        ? null
                        : '${product.model} · ${product.name}',
                  );
                  if (picked == null) return;
                  // force: the column is not inline-editable (the dialog is
                  // the only writer), otherwise the guard drops the change.
                  rendererContext.stateManager.changeCellValue(
                    rendererContext.cell,
                    picked.join(', '),
                    force: true,
                  );
                },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  rendererContext.cell.value,
                  style: _cellTextStyle(context),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!readOnly) const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
        ),
        minWidth: 160,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableTitleChecked: false,
      ),
      TrinaColumn(
        title: context.l10n.productActionsColumn,
        field: 'status',
        // Room for delete + done + undo (three compact 36px buttons).
        width: 120,
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
          // Compact: three buttons share one 120px cell.
          final compact = IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
          return OverflowBar(
            alignment: MainAxisAlignment.spaceAround,
            children: [
              if (!readOnly)
                IconButton(
                  icon: Icon(Icons.delete),
                  style: compact,
                  onPressed: () async {
                    final toDelete = GetIt.I
                        .get<ProductsController>()
                        .products[rendererContext.row.cells['id']!.value];
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
                  style: compact,
                  onPressed: () async {
                    await GetIt.I.get<ProductsController>().save(
                      model: rendererContext.row.cells['id']!.value,
                      name: rendererContext.row.cells['name']!.value,
                      sizes: Product.parseSizeList(
                        rendererContext.row.cells['sizes']!.value as String? ??
                            '',
                      ),
                    );
                    rendererContext.row.cells['status']!.value = 'saved';

                    stateManager.commitChanges(
                      cell: rendererContext.row.cells['id']!,
                    );
                    stateManager.commitChanges(
                      cell: rendererContext.row.cells['name']!,
                    );
                    stateManager.commitChanges(
                      cell: rendererContext.row.cells['sizes']!,
                    );
                    stateManager.setEditing(false);
                    updateDirtyCount();
                  },
                ),
                IconButton(
                  icon: Icon(Icons.undo),
                  style: compact,
                  onPressed: () {
                    for (final cell in rendererContext.row.cells.values) {
                      stateManager.revertChanges(cell: cell);
                    }
                    stateManager.setEditing(false);
                    updateDirtyCount();
                    rendererContext.cell.value = 'saved';
                    stateManager.notifyListenersOnPostFrame();
                  },
                ),
              ],
            ],
          );
        },
      ),
    ];
  }

  List<TrinaRow> _buildRows() {
    return GetIt.I
        .get<ProductsController>()
        .products
        .values
        .map(
          (p) => TrinaRow(
            cells: {
              'id': TrinaCell(value: p.model),
              'name': TrinaCell(value: p.name),
              'sizes': TrinaCell(value: p.sizes.join(', ')),
              'status': TrinaCell(value: 'saved'),
            },
          ),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    rows = _buildRows();
  }

  /// Manual refresh (invoked after the header runs a sync): reload the
  /// controller, then remount the grid — but never drop unsaved edits, so a
  /// dirty grid keeps its rows (fresh data appears on next rebuild).
  Future<void> _refresh() async {
    await GetIt.I.get<ProductsController>().reload();
    if (_disposed || !mounted) return;
    if (widget.unsavedProductCountNotifier.value == 0) {
      setState(() {
        rows = _buildRows();
        _gridTick++;
      });
    }
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
    final auth = AuthService.instance;
    return StreamBuilder<UserRole?>(
      stream: auth.currentRoleStream,
      initialData: auth.currentRole,
      builder: (context, snapshot) {
        // Fail-open while signed out: local editing keeps working offline;
        // the database remains the enforcer for signed-in roles.
        final readOnly = auth.isSignedIn && !auth.canEditCatalog;
        _readOnly = readOnly;
        return Stack(
          children: [
            SizedBox(
              width: 1024,
              height: context.height,
              child: TrinaGrid(
                key: ValueKey(_gridTick),
                columns: _buildColumns(context, readOnly),
                rows: rows,
                onChanged: (TrinaGridOnChangedEvent event) {
                  if (_readOnly) return;
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
                        style: _cellTextStyle(
                          context,
                        ).copyWith(color: context.colorScheme.onErrorContainer),
                      ),

                      behavior: SnackBarBehavior.floating,
                      width: min(700, context.width * .8),
                      backgroundColor: context.colorScheme.errorContainer,
                      duration: Duration(seconds: 10),
                    ),
                  );

                  stateManager.setEditing(false);
                },
                createHeader: (stateManager) => TrinaTableHeader(
                  addNewText: context.l10n.addProduct,
                  showAdd: !readOnly,
                  onRefresh: _refresh,
                  unSavedCountText: (count) =>
                      context.l10n.unsavedProductsCount(count),
                  unSavedCountNotifier: widget.unsavedProductCountNotifier,
                  stateManager: stateManager,
                  newRow: () => TrinaRow(
                    cells: {
                      'id': TrinaCell(value: 'new'),
                      'name': TrinaCell(value: 'new'),
                      'sizes': TrinaCell(value: ''),
                      'status': TrinaCell(value: 'created'),
                    },
                  ),
                ),

                configuration: TrinaGridConfiguration(
                  enterKeyAction: TrinaGridEnterKeyAction.editingAndMoveRight,
                  style: TrinaGridStyleConfig(
                    cellDirtyColor: AppColors.dirtyCell,
                    borderColor: context.colorScheme.surfaceDim,
                    gridBorderColor: context.colorScheme.surfaceDim,
                    gridBorderRadius: BorderRadius.circular(AppRadii.card),
                    cellTextStyle: _cellTextStyle(context),
                    columnTextStyle: _columnTextStyle(context),
                    evenRowColor: context.colorScheme.surfaceContainerLowest,
                    oddRowColor: context.colorScheme.surface,
                  ),
                  scrollbar: TrinaGridScrollbarConfig(
                    showHorizontal: false,
                    showVertical: false,
                  ),
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
                  stateManager.setAutoEditing(!_readOnly);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
