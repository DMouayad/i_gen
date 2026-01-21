import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/futuristic.dart';
import 'package:i_gen/widgets/trina_drop_down_renderer.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:trina_grid/trina_grid.dart';

const _defaultEmptyRowsCount = 10;

class InvoiceTable extends StatefulWidget {
  const InvoiceTable(this.controller, {super.key});
  final InvoiceDetailsController controller;
  @override
  State<InvoiceTable> createState() => InvoiceTableState();
}

class InvoiceTableState extends State<InvoiceTable> {
  Timer? _debounce;
  late final List<TrinaColumn> columns;
  ({String? name, String currency}) selectedPriceCategory = (
    currency: 'USD',
    name: null,
  );

  final products = GetIt.I.get<ProductsController>().products;
  var textStyle = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.bold,
    color: Colors.black,
  );
  double discount = 0;
  String formatNumber(num n) {
    return switch (selectedPriceCategory.currency) {
      'SP' => NumberFormat.decimalPatternDigits(decimalDigits: 0).format(n),
      'USD' => NumberFormat.decimalPatternDigits(decimalDigits: 2).format(n),
      _ => NumberFormat.decimalPatternDigits(decimalDigits: 0).format(n),
    };
  }

  Widget _cellRenderer(
    TrinaColumnRendererContext rendererContext, [
    bool format = true,
  ]) {
    if (rendererContext.column.field == 'line_total') {
      final amount = rendererContext.cell.row.cells['amount']!.value;
      final unitPrice = rendererContext.cell.row.cells['unit_price']!.value;
      if (amount is num && unitPrice is num) {
        final lineTotal = unitPrice * amount;
        rendererContext.cell.value = lineTotal;
        stateManager.notifyListeners();
        if (lineTotal > 0) {
          return Text(
            formatNumber(lineTotal),
            style: textStyle,
            textAlign: TextAlign.center,
          );
        }
      }
    }

    return Text(
      switch (rendererContext.cell.value) {
        null || 0 => '',
        int n => format ? formatNumber(n) : n.toString(),
        double d => format ? formatNumber(d) : d.toString(),
        _ => rendererContext.cell.value,
      },
      style: textStyle,
      textAlign: TextAlign.center,
    );
  }

  late final ProductsPricing productsPricing;

  double tableHeight = 0;
  final double tableRowHeight = 52;
  final double extraHeight = 85;
  final double footerExpandedHeight = 135;
  final double heightToAddWhenFooterIsExpanded = 104;
  double getTotal(TrinaGridStateManager stateManager) {
    final lineTotals = stateManager.refRows
        .map((e) => (e.cells['line_total']!.value as num).toDouble())
        .toList();
    if (lineTotals.isNotEmpty) {
      return lineTotals.reduce((value, element) => value + element);
    }
    return 0;
  }

  double getTotalWithDiscount(
    TrinaColumnFooterRendererContext rendererContext,
  ) {
    return getTotal(rendererContext.stateManager) - discount;
  }

  NumberFormat getNumberFormat() {
    return NumberFormat.currency(
      decimalDigits: selectedPriceCategory.currency == 'USD' ? 1 : 0,
      symbol: selectedPriceCategory.currency == 'SP' ? ' ل.س' : '\$ ',
      locale: selectedPriceCategory.currency == 'SP' ? 'ar' : 'en',
    );
  }

  @override
  void initState() {
    widget.controller.textSizeNotifier.addListener(() {
      setState(() {
        textStyle = textStyle.copyWith(
          fontSize: widget.controller.textSizeNotifier.value.toDouble(),
        );
      });
    });
    discount = widget.controller.discount;
    if (widget.controller.invoice?.currency case String currency) {
      selectedPriceCategory = (currency: currency, name: null);
    }
    columns = [
      TrinaColumn(
        title: 'Model'.toUpperCase(),
        field: 'id',
        type: TrinaColumnType.select(products.keys.map((e) => e).toList()),
        enableEditingMode: true,
        minWidth: 80,
        enableAutoEditing: true,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableContextMenu: false,
        textAlign: TrinaColumnTextAlign.center,
        titleTextAlign: TrinaColumnTextAlign.center,
        renderer: _cellRenderer,
        editCellRenderer:
            (
              defaultEditCellWidget,
              cell,
              controller,
              focusNode,
              handleSelected,
            ) => trinaDropDownRenderer(
              context,
              defaultEditCellWidget,
              cell,
              controller,
              focusNode,
              handleSelected,
              (newValue) {
                cell.row.cells['desc']!.value = products[newValue]?.name;
              },
            ),
      ),
      TrinaColumn(
        title: 'Description'.toUpperCase(),
        field: 'desc',
        enableAutoEditing: true,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableContextMenu: false,
        minWidth: 340,
        renderer: _cellRenderer,
        titleTextAlign: TrinaColumnTextAlign.center,
        footerRenderer: (_) {
          return Container(
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.black26)),
            ),
            child: Text(
              'Thank you for your business'.toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          );
        },
        editCellRenderer:
            (
              defaultEditCellWidget,
              cell,
              controller,
              focusNode,
              handleSelected,
            ) => trinaDropDownRenderer(
              context,
              defaultEditCellWidget,
              cell,
              controller,
              focusNode,
              handleSelected,
              (newValue) {
                final prod = products.values.firstWhere(
                  (element) => element.name == newValue,
                );
                cell.row.cells['id']!.value = prod.model;
              },
            ),
        textAlign: TrinaColumnTextAlign.center,
        type: TrinaColumnType.select(
          products.values.map((e) => e.name).toList(),
        ),
      ),
      TrinaColumn(
        enableContextMenu: false,
        enableColumnDrag: false,
        enableDropToResize: false,
        enableAutoEditing: true,
        renderer: (rendererContext) => _cellRenderer(rendererContext, false),
        titleTextAlign: TrinaColumnTextAlign.center,
        title: 'QTY',
        field: 'amount',
        minWidth: 70,
        type: TrinaColumnType.number(negative: false, allowFirstDot: false),
      ),
      TrinaColumn(
        enableColumnDrag: false,
        enableAutoEditing: true,
        enableContextMenu: false,
        enableDropToResize: false,
        renderer: (rendererContext) {
          if (selectedPriceCategory.name == null) {
            return _cellRenderer(rendererContext);
          }
          final price = _getModelPriceByCategory(
            rendererContext.row.cells['id']!.value,
            rendererContext.row.cells['price_category']!.value,
          );
          rendererContext.cell.value = price ?? 0;
          return Text(
            price != null ? formatNumber(price) : '',
            style: textStyle,
            textAlign: TextAlign.center,
          );
        },
        titleTextAlign: TrinaColumnTextAlign.center,
        title: 'Unit Price'.toUpperCase(),
        field: 'unit_price',
        minWidth: 150,
        type: TrinaColumnType.number(
          format: "#,###.##",
          negative: false,
          allowFirstDot: false,
          defaultValue: '',
        ),
        footerRenderer: (_) {
          return Container(
            padding: EdgeInsets.only(left: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  discount > 0 ? 'Subtotal' : 'TOTAL',
                  style: textStyle.copyWith(fontSize: 16),
                ),
                if (discount > 0 || widget.controller.editingIsEnabled) ...[
                  SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) {
                          return Dialog(
                            child: Container(
                              height: 80,
                              width: 300,
                              padding: EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 20,
                              ),
                              child: TextFormField(
                                autofocus: true,
                                initialValue: discount > 0
                                    ? discount.toString()
                                    : null,
                                style: textStyle,

                                onFieldSubmitted: (value) {
                                  Navigator.of(context).pop();
                                  setState(() {
                                    discount = double.tryParse(value) ?? 0;
                                  });
                                  widget.controller.discount = discount;
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                    child: Text(
                      'Discount',
                      style: textStyle.copyWith(
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text('TOTAL', style: textStyle.copyWith(fontSize: 16)),
                ],
              ],
            ),
          );
        },
      ),
      TrinaColumn(
        enableColumnDrag: false,
        enableContextMenu: false,
        enableDropToResize: false,
        renderer: _cellRenderer,
        titleTextAlign: TrinaColumnTextAlign.center,
        textAlign: TrinaColumnTextAlign.center,
        title: 'Line Total'.toUpperCase(),
        field: 'line_total',
        minWidth: 200,
        enableAutoEditing: false,
        type: TrinaColumnType.number(
          negative: false,
          allowFirstDot: false,
          defaultValue: '',
        ),
        footerRenderer: (rendererContext) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                flex: 0,
                child: TrinaAggregateColumnFooter(
                  rendererContext: rendererContext,
                  type: TrinaAggregateColumnType.sum,
                  alignment: Alignment.center,
                  numberFormat: NumberFormat.decimalPatternDigits(
                    locale: getNumberFormat().locale,
                    decimalDigits: getNumberFormat().decimalDigits,
                  ),
                  titleSpanBuilder: (sumValue) {
                    final numberFormat = getNumberFormat();
                    return [
                      WidgetSpan(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$sumValue ${numberFormat.currencySymbol}',
                              style: textStyle.copyWith(
                                fontSize: textStyle.fontSize! + 1,
                              ),
                              textDirection: numberFormat.locale == 'en'
                                  ? TextDirection.rtl
                                  : TextDirection.rtl,
                              // locale: Locale(numberFormat.locale),
                            ),
                            if (discount > 0 ||
                                widget.controller.editingIsEnabled) ...[
                              SizedBox(height: 10),
                              Text(
                                '- ${numberFormat.format(discount)}',
                                style: textStyle.copyWith(
                                  fontSize: textStyle.fontSize! + 1,
                                ),
                                textAlign: TextAlign.start,
                              ),
                              SizedBox(height: 10),
                              Text(
                                numberFormat.format(
                                  getTotalWithDiscount(rendererContext),
                                ),
                                style: textStyle.copyWith(
                                  fontSize: textStyle.fontSize! + 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ];
                  },
                ),
              ),
            ],
          );
        },
      ),
      TrinaColumn(
        title: '',
        field: 'price_category',
        width: 200,
        hide: !widget.controller.editingIsEnabled,
        enableRowDrag: true,
        enableEditingMode: false,
        enableDropToResize: false,
        enableContextMenu: false,
        enableColumnDrag: false,
        frozen: TrinaColumnFrozen.end,
        footerRenderer: (context) {
          return IconButton.filled(
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
            ),
            onPressed: () {
              setState(() {
                tableHeight += tableRowHeight;
              });
              stateManager.insertRows(stateManager.refRows.last.sortIdx + 1, [
                _newEmptyRow(),
              ]);
              final newLastRow = stateManager.refRows.last;
              stateManager.moveScrollByRow(
                TrinaMoveDirection.down,
                newLastRow.sortIdx,
              );

              stateManager.setHoveredRowIdx(newLastRow.sortIdx);
            },
            icon: Icon(Icons.add),
          );
        },
        titleRenderer: (rendererContext) {
          final style = textStyle.copyWith(fontSize: 18);
          return SizedBox(
            width: 200,
            height: 60,
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.center,
              child: Futuristic(
                autoStart: true,
                key: Key('priceCategoryDropdown'),
                futureBuilder: () =>
                    GetIt.I.get<PricingCategoryRepo>().getAll(),
                dataBuilder: (context, categories) {
                  return DropdownButtonHideUnderline(
                    child: DropdownButton(
                      padding: EdgeInsets.zero,
                      icon: const SizedBox.shrink(),
                      value: selectedPriceCategory,
                      style: style,
                      hint: const Text('Select price list'),
                      items: [
                        const DropdownMenuItem(
                          value: (currency: 'SP', name: null),
                          child: Text(
                            'Custom ل.س',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const DropdownMenuItem(
                          value: (currency: 'USD', name: null),
                          child: Text('Custom \$', textAlign: TextAlign.center),
                        ),
                        ...categories.map(
                          (e) => DropdownMenuItem(
                            value: (currency: e.currency, name: e.name),
                            child: Text(
                              '${e.name} (${e.currency})',
                              style: style,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (newValue) {
                        if (newValue == null) {
                          return;
                        }
                        widget.controller.currency = newValue.currency;
                        setState(() {
                          selectedPriceCategory = newValue;
                        });
                        for (var row in stateManager.refRows) {
                          row.cells['price_category']!.value = newValue.name;
                        }
                        _updateControllerLines();
                      },
                    ),
                  );
                },
              ),
            ),
          );
        },
        renderer: (rendererContext) => SizedBox(
          width: 55,
          child: IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            alignment: AlignmentDirectional.centerEnd,
            onPressed: () {
              rendererContext.stateManager.removeRows([rendererContext.row]);
              setState(() {
                tableHeight -= tableRowHeight;
              });
            },
          ),
        ),
        type: TrinaColumnType.text(),
      ),
    ];

    int emptyRowsToAdd =
        _defaultEmptyRowsCount - widget.controller.invoiceLines.length;
    emptyRowsToAdd = emptyRowsToAdd > 0 ? emptyRowsToAdd : 0;
    tableHeight =
        (widget.controller.invoiceLines.isEmpty
            ? _defaultEmptyRowsCount * tableRowHeight
            : (widget.controller.invoiceLines.length + emptyRowsToAdd) *
                  tableRowHeight) +
        extraHeight +
        ((discount > 0 || widget.controller.editingIsEnabled)
            ? heightToAddWhenFooterIsExpanded
            : 0);

    fetchRows().then((fetchedRows) {
      TrinaGridStateManager.initializeRowsAsync(columns, fetchedRows).then((
        value,
      ) {
        stateManager.refRows.addAll(value);
        stateManager.notifyListeners();
      });
    });
    super.initState();
  }

  Future<List<TrinaRow>> fetchRows() async {
    productsPricing = await GetIt.I
        .get<ProductPricingRepo>()
        .getProductsPricing();
    if (widget.controller.invoiceLines.isNotEmpty) {
      var rows = widget.controller.invoiceLines.map((e) {
        return TrinaRow(
          cells: {
            'id': TrinaCell(value: e.product.model),
            'desc': TrinaCell(value: e.product.name),
            'amount': TrinaCell(value: e.amount),
            'unit_price': TrinaCell(value: e.unitPrice),
            'line_total': TrinaCell(value: e.lineTotal),
            'price_category': TrinaCell(value: selectedPriceCategory.name),
          },
        );
      }).toList();
      final emptyRowsToAdd =
          _defaultEmptyRowsCount - widget.controller.invoiceLines.length;
      if (emptyRowsToAdd > 0) {
        rows.addAll(List.generate(emptyRowsToAdd, (index) => _newEmptyRow()));
      }

      return rows;
    } else {
      return List.generate(_defaultEmptyRowsCount, (index) => _newEmptyRow());
    }
  }

  TrinaRow _newEmptyRow() {
    return TrinaRow(
      cells: {
        'id': TrinaCell(value: null),
        'desc': TrinaCell(value: null),
        'amount': TrinaCell(value: 0),
        'unit_price': TrinaCell(value: 0),
        'line_total': TrinaCell(value: 0),
        'price_category': TrinaCell(value: selectedPriceCategory.name),
      },
    );
  }

  late final TrinaGridStateManager stateManager;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: tableHeight,
      child: TrinaGrid(
        configuration: TrinaGridConfiguration(
          enterKeyAction: TrinaGridEnterKeyAction.editingAndMoveRight,
          columnSize: TrinaGridColumnSizeConfig(
            autoSizeMode: TrinaAutoSizeMode.scale,
          ),
          enableMoveHorizontalInEditing: true,
          style: TrinaGridStyleConfig(
            rowHeight: tableRowHeight,
            cellTextStyle: textStyle,
            gridBorderColor: context.colorScheme.surfaceDim,
            borderColor: context.colorScheme.surfaceDim,
            enableColumnBorderHorizontal: false,
            enableCellBorderHorizontal: false,
            enableColumnBorderVertical: false,
          ),
          scrollbar: TrinaGridScrollbarConfig(
            showHorizontal: false,
            showVertical: false,
          ),
        ),
        columns: columns,
        rows: [],
        onChanged: (event) => _updateControllerLines(),
        onLoaded: (event) {
          stateManager = event.stateManager;

          if (widget.controller.editingIsEnabled || discount > 0) {
            stateManager.columnFooterHeight = footerExpandedHeight;
          }
          widget.controller.enableEditingNotifier.addListener(() {
            final isEditing = widget.controller.editingIsEnabled;
            stateManager.hideColumn(columns.last, !isEditing);
            if (isEditing) {
              onEnableEditing();
            } else {
              onDisableEditing();
            }
          });

          stateManager.setShowColumnFilter(false);
        },
      ),
    );
  }

  void _updateControllerLines() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.controller.hasUnsavedChanges = true;
      final invoiceRows = <InvoiceTableRow>[];
      for (var row in stateManager.refRows) {
        if (row.cells['id']!.value case String model) {
          invoiceRows.add(
            InvoiceTableRow(
              unitPrice: row.cells['unit_price']!.value,
              product: products[model]!,
              amount: row.cells['amount']!.value,
            ),
          );
        }
      }
      widget.controller.invoiceLines = invoiceRows;
      widget.controller.reCalculateTotal();
    });
  }

  void onEnableEditing() {
    stateManager.columnFooterHeight = footerExpandedHeight;
    if (discount <= 0) {
      setState(() {
        tableHeight += heightToAddWhenFooterIsExpanded;
      });
    }
  }

  Future<void> onDisableEditing() async {
    if (discount <= 0) {
      stateManager.columnFooterHeight = stateManager.rowTotalHeight;
      setState(() {
        tableHeight -= heightToAddWhenFooterIsExpanded;
      });
    }
  }

  double? _getModelPriceByCategory(String? model, String? pricingCategory) {
    if (model == null || pricingCategory == null) {
      return null;
    }
    return productsPricing[model]?[pricingCategory]?.price;
  }
}
