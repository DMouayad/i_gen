import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/constants.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/utils/context_extensions.dart';
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

  final textStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
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

  @override
  void initState() {
    columns.add(
      TrinaColumn(
        title: 'Model',
        field: 'model',
        type: TrinaColumnType.text(),
        width: 100,
        textAlign: TrinaColumnTextAlign.center,
        frozen: TrinaColumnFrozen.start,
        enableContextMenu: false,
        enableEditingMode: false,
      ),
    );
    columns.add(
      TrinaColumn(
        title: 'Actions',
        field: 'status',
        width: 130,
        enableEditingMode: false,
        frozen: TrinaColumnFrozen.end,
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
                TextButton.icon(
                  label: Text('Undo'),
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
    );

    fetchCols().then((fetchedColumns) {
      stateManager.insertColumns(2, fetchedColumns);
    });
    fetchRows().then((fetchedRows) {
      TrinaGridStateManager.initializeRowsAsync(columns, fetchedRows).then((
        value,
      ) {
        stateManager.refRows.addAll(value);
        stateManager.setShowLoading(false);
      });
    });

    super.initState();
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
      width: 150,
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
          child: TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder:
                    (context) => _EditPriceCategoryDialog(
                      name: name,
                      currency: currency,
                      priceCategoryId: priceCategoryId,
                      existingCategories: pricingCategories,
                      rendererContext: rendererContext,
                    ),
              );
            },
            iconAlignment: IconAlignment.end,
            label: Text(
              '${rendererContext.column.title} (${currencies[currency]}) ',
              style: textStyle,
            ),
            icon: Icon(Icons.edit),
          ),
        );
      },
    );
  }

  Future<List<TrinaRow>> fetchRows() async {
    final productsPricing =
        await GetIt.I.get<ProductPricingRepo>().getProductsPricing();
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
    return TrinaGrid(
      columns: columns,
      rows: [],
      onChanged: (TrinaGridOnChangedEvent event) {
        updateDirtyCount();
        dirtyRows.add(event.rowIdx);
        print(event);
        for (var cell in event.row.cells.values) {
          print('${cell.value}: ${cell.isDirty}');
        }
        if (event.row.cells['status']!.value == 'saved') {
          event.row.cells['status']!.value = 'edited';
        }
      },
      configuration: TrinaGridConfiguration(
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
      ),
      createHeader: (stateManager) {
        return Container(
          height: 70,
          // width: 140,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder(
                valueListenable: widget.unsavedProductPricingCountNotifier,
                builder: (context, value, child) {
                  return value <= 0
                      ? SizedBox.shrink()
                      : TextButton.icon(
                        label: Text(
                          'Save All',
                          style: textStyle.copyWith(
                            color: context.colorScheme.primary,
                          ),
                        ),
                        icon: Icon(Icons.save),
                        onPressed: () async {
                          stateManager.setShowLoading(true);
                          for (final rowId in dirtyRows) {
                            var row = stateManager.refRows[rowId];
                            for (final cell in row.cells.values) {
                              if (cell.isDirty) {
                                final priceCategory = pricingCategories
                                    .firstWhere(
                                      (element) =>
                                          element.name == cell.column.title,
                                    );
                                await GetIt.I.get<ProductPricingRepo>().save(
                                  priceCategoryId: priceCategory.id,
                                  productId:
                                      products[row.cells['model']!.value]!.id,
                                  price: cell.value,
                                  currency: priceCategory.currency,
                                );
                              }
                              stateManager.commitChanges(cell: cell);
                              stateManager
                                  .refRows[rowId]
                                  .cells['status']!
                                  .value = 'saved';
                            }
                          }
                          stateManager.setShowLoading(false);
                          dirtyRows.clear();
                          updateDirtyCount();
                        },
                      );
                },
              ),
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.colorScheme.surfaceDim),
                  ),
                ),
                child: TextButton.icon(
                  onPressed: () async {
                    final currency = currencies.keys.first;

                    final res = await showDialog(
                      context: context,
                      builder:
                          (context) => _EditPriceCategoryDialog(
                            name: '',
                            currency: currency,
                            existingCategories: pricingCategories,
                          ),
                    );
                    if (res case (int id, String name, String currency)) {
                      final index = stateManager.refColumns.length;
                      final newCol = _getColumn(name, currency);
                      stateManager.insertColumns(index, [newCol]);
                      pricingCategories.add(
                        PriceCategory(id: id, name: name, currency: currency),
                      );
                    }
                  },
                  label: Text(
                    'New List',
                    style: textStyle.copyWith(
                      // color: context.colorScheme.primary,
                    ),
                  ),
                  icon: Icon(Icons.add_box),
                ),
              ),
            ],
          ),
        );
      },
      onLoaded: (TrinaGridOnLoadedEvent event) {
        stateManager = event.stateManager;

        /// When the grid is finished loading, enable loading.
        stateManager.setChangeTracking(true);
        stateManager.setAutoEditing(true);
        stateManager.setShowLoading(true);
      },
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
  final textStyle = TextStyle(
    fontSize: 20,
    color: Colors.black,
    fontWeight: FontWeight.w600,
  );
  final labelTextStyle = TextStyle(fontSize: 16, color: Colors.black);
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
    const spacer = SizedBox(height: 20);
    return Dialog(
      child: Form(
        key: formKey,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 400, maxHeight: 350),
          child: ListView(
            padding: EdgeInsets.all(50),
            children: [
              if (widget.priceCategoryId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Edit or Delete this list'),
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
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ),
              TextFormField(
                initialValue: widget.name,
                style: textStyle,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: 'Enter name',
                ),
                onChanged: (value) => newName = value,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Name is required';
                  }
                  if (widget.existingCategories.any(
                    (element) =>
                        element.name == value && element.name != widget.name,
                  )) {
                    return 'Name already exists';
                  }
                  return null;
                },
              ),
              spacer,
              DropdownButtonFormField<String>(
                value: widget.currency,
                decoration: InputDecoration(
                  labelText: 'Currency',
                  hintText: 'Enter currency',
                ),
                isDense: false,
                style: textStyle,

                items:
                    currencies.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  newCurrency = value ?? '';
                },
              ),

              SizedBox(height: 40),

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
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
