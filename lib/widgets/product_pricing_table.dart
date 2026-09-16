import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/auth/auth_service.dart';
import 'package:i_gen/constants.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/read_only_banner.dart';
import 'package:i_gen/widgets/sync_spinner.dart';
import 'package:trina_grid/trina_grid.dart';

class ProductPricingTable extends StatefulWidget {
  const ProductPricingTable(
    this.unsavedProductPricingCountNotifier,
    this.unsavedPricingCategoryCountNotifier, {
    super.key,
  });
  final ValueNotifier<int> unsavedProductPricingCountNotifier;
  final ValueNotifier<int> unsavedPricingCategoryCountNotifier;

  @override
  State<ProductPricingTable> createState() => _ProductPricingTableState();
}

class _ProductPricingTableState extends State<ProductPricingTable> {
  final List<TrinaColumn> columns = [];

  late TrinaGridStateManager stateManager;
  final products = GetIt.I.get<ProductsController>().products;
  List<PriceCategory> pricingCategories = [];
  final Set<int> dirtyRows = {};

  bool _disposed = false;

  TextStyle _cellTextStyle(BuildContext context) =>
      context.textTheme.bodyLarge!.copyWith(
        fontWeight: FontWeight.bold,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle _columnTextStyle(BuildContext context) =>
      _cellTextStyle(context).copyWith(color: context.colorScheme.primary);

  /// Role read-only mirror for renderers created outside build (title
  /// editors, header actions). Fail-open while signed out so local editing
  /// keeps working offline; the database remains the enforcer.
  final ValueNotifier<bool> _readOnlyNotifier = ValueNotifier(false);
  StreamSubscription<UserRole?>? _roleSub;
  bool _gridReady = false;

  @override
  void dispose() {
    _disposed = true;
    _roleSub?.cancel();
    _readOnlyNotifier.dispose();
    super.dispose();
  }

  void updateDirtyCount() {
    if (_disposed) return;

    // Use Future.microtask to ensure we're not updating during build or dispose
    Future.microtask(() {
      if (_disposed) return;

      int count = 0;
      for (var row in stateManager.refRows) {
        for (var cell in row.cells.values) {
          if (cell.isDirty) {
            count++;
          }
        }
      }
      if (!_disposed) {
        widget.unsavedProductPricingCountNotifier.value = count;
      }
    });
  }

  bool _columnsInitialized = false;
  int _gridTick = 0;

  /// Manual refresh (invoked after a sync): remount the grid so columns and
  /// rows rebuild from the repos — but never drop unsaved edits, so a dirty
  /// grid keeps its state (fresh data appears on next rebuild).
  Future<void> _refresh() async {
    if (_disposed || !mounted) return;
    if (dirtyRows.isEmpty &&
        widget.unsavedProductPricingCountNotifier.value == 0 &&
        widget.unsavedPricingCategoryCountNotifier.value == 0) {
      setState(() => _gridTick++);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Column titles need l10n (an inherited widget), which is illegal in
    // initState. Build once here; later dependency changes (e.g. theme)
    // must not rebuild columns or grid state would reset.
    if (_columnsInitialized) return;
    _columnsInitialized = true;
    columns.add(
      TrinaColumn(
        title: context.l10n.productModel,
        field: 'model',
        type: TrinaColumnType.text(),
        width: 70,
        textAlign: TrinaColumnTextAlign.center,
        frozen: TrinaColumnFrozen.start,
        enableContextMenu: false,
        enableEditingMode: false,
      ),
    );
    columns.add(
      TrinaColumn(
        title: '',
        field: 'status',
        width: 70,
        enableEditingMode: false,
        frozen: TrinaColumnFrozen.end,
        enableContextMenu: false,
        enableDropToResize: false,
        enableColumnDrag: false,
        type: TrinaColumnType.select(<String>[
          'saved',
          'edited',
          'created',
          'error',
        ]),

        renderer: (rendererContext) {
          return OverflowBar(
            alignment: MainAxisAlignment.spaceAround,
            children: [
              if (rendererContext.cell.value == 'edited') ...[
                IconButton(
                  icon: Icon(Icons.undo),
                  onPressed: () {
                    final cells = rendererContext.row.cells.values;
                    for (final cell in cells) {
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
    );
  }

  @override
  void initState() {
    super.initState();
    final auth = AuthService.instance;
    _readOnlyNotifier.value = auth.isSignedIn && !auth.canEditCatalog;
    _roleSub = auth.currentRoleStream.listen((_) {
      if (_disposed) return;
      _readOnlyNotifier.value = auth.isSignedIn && !auth.canEditCatalog;
      if (_gridReady) {
        stateManager.setAutoEditing(!_readOnlyNotifier.value);
      }
    });
    _loadGrid();
  }

  Future<void> _loadGrid() async {
    final fetchedColumns = await fetchCols();
    // must insert before building rows: fetchRows reads columns.skip(2)
    stateManager.insertColumns(2, fetchedColumns);
    final fetchedRows = await fetchRows();
    final rows = await TrinaGridStateManager.initializeRowsAsync(
      columns,
      fetchedRows,
    );
    if (_disposed) return;
    stateManager.refRows.addAll(rows);
    stateManager.setShowLoading(false);
  }

  Future<List<TrinaColumn>> fetchCols() async {
    final categories = await GetIt.I.get<PricingCategoryRepo>().getAll();
    pricingCategories = categories;
    return pricingCategories
        .map((e) => _getColumn(e.name, e.currency, priceCategoryId: e.id))
        .toList();
  }

  TrinaColumn _getColumn(String name, String currency, {int? priceCategoryId}) {
    return TrinaColumn(
      title: name,
      field: name,
      type: TrinaColumnType.number(negative: false, allowFirstDot: false),
      width: 140,
      enableColumnDrag: true,
      enableDropToResize: true,
      textAlign: TrinaColumnTextAlign.center,
      titleRenderer: (rendererContext) {
        return Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: context.colorScheme.surfaceDim),
            ),
          ),
          child: ValueListenableBuilder<bool>(
            valueListenable: _readOnlyNotifier,
            builder: (context, readOnly, _) {
              final label = Text(
                context.l10n.priceCategoryColumnTitle(
                  rendererContext.column.title,
                  currencies[currency] ?? currency,
                ),
                style: _cellTextStyle(context),
              );
              if (readOnly) return Center(child: label);
              return TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => _EditPriceCategoryDialog(
                      name: name,
                      currency: currency,
                      priceCategoryId: priceCategoryId,
                      existingCategories: pricingCategories,
                      rendererContext: rendererContext,
                    ),
                  );
                },
                iconAlignment: IconAlignment.end,
                label: label,
                icon: Icon(Icons.edit),
              );
            },
          ),
        );
      },
    );
  }

  Future<List<TrinaRow>> fetchRows() async {
    final productsPricing = await GetIt.I
        .get<ProductPricingRepo>()
        .getProductsPricing();
    return productsPricing.entries.map((e) {
      return TrinaRow(
        cells: {
          'model': TrinaCell(value: e.key),
          ...Map.fromEntries(
            // skip (model, status) columns
            columns.skip(2).map((col) {
              return MapEntry(
                col.field,
                TrinaCell(value: e.value[col.field]?.price),
              );
            }),
          ),
          'status': TrinaCell(value: 'saved'),
        },
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: context.isMobile ? context.width : 920,
          ),
          child: TrinaGrid(
            key: ValueKey(_gridTick),
            columns: columns,
            rows: [],
            onChanged: (TrinaGridOnChangedEvent event) {
              if (_readOnlyNotifier.value) return;
              updateDirtyCount();
              dirtyRows.add(event.rowIdx);

              if (event.row.cells['status']!.value == 'saved') {
                event.row.cells['status']!.value = 'edited';
              }
            },
            configuration: TrinaGridConfiguration(
              style: TrinaGridStyleConfig(
                cellDirtyColor: context.colorScheme.tertiaryContainer,
                borderColor: context.colorScheme.surfaceDim,
                gridBorderColor: context.colorScheme.surfaceDim,
                gridBorderRadius: BorderRadius.circular(AppRadii.card),
                cellTextStyle: _cellTextStyle(context),
                columnTextStyle: _columnTextStyle(context),
                evenRowColor: context.colorScheme.surfaceContainerLowest,
                oddRowColor: context.colorScheme.surface,
              ),
            ),
            createHeader: (stateManager) {
              return ValueListenableBuilder<bool>(
                valueListenable: _readOnlyNotifier,
                builder: (context, readOnly, _) {
                  return Container(
                    height: 48,
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder(
                          valueListenable:
                              widget.unsavedProductPricingCountNotifier,
                          builder: (context, value, child) {
                            return value <= 0 || readOnly
                                ? SizedBox.shrink()
                                : TextButton.icon(
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(64, 48),
                                    ),
                                    label: Text(
                                      context.l10n.saveAllButton,
                                      style: _columnTextStyle(context),
                                    ),
                                    icon: Icon(Icons.save),
                                    onPressed: () async {
                                      stateManager.setShowLoading(true);
                                      for (final rowId in dirtyRows) {
                                        var row = stateManager.refRows[rowId];
                                        for (final cell in row.cells.values) {
                                          if (cell.isDirty) {
                                            final priceCategory =
                                                pricingCategories.firstWhere(
                                                  (element) =>
                                                      element.name ==
                                                      cell.column.title,
                                                );
                                            await GetIt.I
                                                .get<ProductPricingRepo>()
                                                .save(
                                                  priceCategoryId:
                                                      priceCategory.id,
                                                  productId:
                                                      products[row
                                                              .cells['model']!
                                                              .value]!
                                                          .id,
                                                  price: cell.value,
                                                  currency:
                                                      priceCategory.currency,
                                                );
                                          }
                                          stateManager.commitChanges(
                                            cell: cell,
                                          );
                                          stateManager
                                                  .refRows[rowId]
                                                  .cells['status']!
                                                  .value =
                                              'saved';
                                        }
                                      }
                                      stateManager.setShowLoading(false);
                                      dirtyRows.clear();
                                      updateDirtyCount();
                                    },
                                  );
                          },
                        ),
                        if (!readOnly)
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(
                                  color: context.colorScheme.surfaceDim,
                                ),
                              ),
                            ),
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(64, 48),
                              ),
                              onPressed: () async {
                                final currency = currencies.keys.first;

                                final res = await showDialog(
                                  context: context,
                                  builder: (context) =>
                                      _EditPriceCategoryDialog(
                                        name: '',
                                        currency: currency,
                                        existingCategories: pricingCategories,
                                      ),
                                );
                                if (res case (
                                  int id,
                                  String name,
                                  String currency,
                                )) {
                                  final index = stateManager.refColumns.length;
                                  final newCol = _getColumn(name, currency);
                                  stateManager.insertColumns(index, [newCol]);
                                  pricingCategories.add(
                                    PriceCategory(
                                      id: id,
                                      name: name,
                                      currency: currency,
                                    ),
                                  );
                                }
                              },
                              label: Text(
                                context.l10n.newPriceList,
                                style: _cellTextStyle(context),
                              ),
                              icon: Icon(Icons.add_box),
                            ),
                          ),
                        Spacer(),
                        const SyncSpinner(),

                        IconButton(
                          tooltip: context.l10n.refresh,
                          icon: const Icon(Icons.refresh),
                          onPressed: () => SyncTrigger.instance.syncNow().then(
                            (_) => _refresh(),
                            onError: (_) => _refresh(),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            onLoaded: (TrinaGridOnLoadedEvent event) {
              stateManager = event.stateManager;

              /// When the grid is finished loading, enable loading.
              stateManager.setChangeTracking(true);
              stateManager.setAutoEditing(!_readOnlyNotifier.value);
              stateManager.setShowLoading(true);
              _gridReady = true;
            },
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _readOnlyNotifier,
          builder: (context, readOnly, _) {
            if (!readOnly) return const SizedBox.shrink();
            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ReadOnlyBanner(text: context.l10n.pricingReadOnlyMessage),
            );
          },
        ),
      ],
    );
  }
}

class _EditPriceCategoryDialog extends StatefulWidget {
  const _EditPriceCategoryDialog({
    required this.name,
    required this.currency,
    required this.existingCategories,
    this.priceCategoryId,
    this.rendererContext,
  }) : assert(
         (priceCategoryId != null && rendererContext != null) ||
             priceCategoryId == null,
       );
  final TrinaColumnTitleRendererContext? rendererContext;
  final String name;
  final String currency;
  final List<PriceCategory> existingCategories;
  final int? priceCategoryId;
  @override
  State<_EditPriceCategoryDialog> createState() =>
      _EditPriceCategoryDialogState();
}

class _EditPriceCategoryDialogState extends State<_EditPriceCategoryDialog> {
  final formKey = GlobalKey<FormState>();
  String newName = '';
  String newCurrency = '';
  @override
  void initState() {
    newName = widget.name;
    newCurrency = widget.currency;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final inputTextStyle = context.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final dialogTitleStyle = context.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final spacer = SizedBox(height: AppGaps.md);
    return Dialog(
      child: Form(
        key: formKey,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400, maxHeight: 350),
          child: ListView(
            padding: EdgeInsets.all(AppGaps.md),
            children: [
              if (widget.priceCategoryId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppGaps.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.l10n.editOrDeleteList),
                      TextButton(
                        onPressed: () async {
                          await GetIt.I.get<PricingCategoryRepo>().delete(
                            widget.priceCategoryId!,
                          );
                          widget.rendererContext!.stateManager.removeColumns([
                            widget.rendererContext!.column,
                          ]);
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                        },
                        style: ButtonStyle(
                          foregroundColor: WidgetStatePropertyAll(
                            context.colorScheme.onError,
                          ),
                          backgroundColor: WidgetStatePropertyAll(
                            context.colorScheme.error,
                          ),
                        ),
                        child: Text(context.l10n.deleteButton),
                      ),
                    ],
                  ),
                ),
              TextFormField(
                initialValue: widget.name,
                style: inputTextStyle,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context.l10n.priceCategoryNameLabel,
                  hintText: context.l10n.priceCategoryNameHint,
                  labelStyle: dialogTitleStyle,
                ),
                onChanged: (value) => newName = value,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return context.l10n.nameRequiredError;
                  }
                  if (widget.existingCategories.any(
                    (element) =>
                        element.name == value && element.name != widget.name,
                  )) {
                    return context.l10n.nameAlreadyExistsError;
                  }
                  return null;
                },
              ),
              spacer,
              DropdownButtonFormField<String>(
                initialValue: widget.currency,
                decoration: InputDecoration(
                  labelText: context.l10n.currencyLabel,
                  hintText: context.l10n.currencyHint,
                  labelStyle: dialogTitleStyle,
                ),
                isDense: false,
                style: inputTextStyle,

                items: currencies.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (value) {
                  newCurrency = value ?? '';
                },
              ),

              SizedBox(height: AppGaps.xl),

              FilledButton.tonal(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    GetIt.I
                        .get<PricingCategoryRepo>()
                        .save(
                          name: newName,
                          currency: newCurrency,
                          id: widget.priceCategoryId,
                        )
                        .then((id) {
                          if (context.mounted) {
                            Navigator.of(
                              context,
                            ).pop((id, newName, newCurrency));
                          }
                        });
                  }
                },
                child: Text(context.l10n.saveButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
