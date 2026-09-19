import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/design/tokens.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/utils/futuristic.dart';
import 'package:i_gen/utils/numbers.dart';
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
  double discount = 0;

  TextStyle _cellTextStyle(BuildContext context) =>
      context.textTheme.bodyLarge!.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontFamily: BrandFonts.arabic,
        fontSize: widget.controller.textSizeNotifier.value.toDouble(),
      );

  TextStyle _smallLabelStyle(BuildContext context) =>
      context.textTheme.bodyMedium!.copyWith(
        fontWeight: FontWeight.w600,
        fontFamily: BrandFonts.arabic,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle _moneyStyle(BuildContext context) =>
      context.textTheme.titleLarge!.copyWith(
        fontWeight: FontWeight.w600,
        fontFamily: BrandFonts.arabic,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  TextStyle _titleRendererStyle(BuildContext context) =>
      context.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600);

  String formatNumber(num n) {
    return NumberFormat.decimalPatternDigits(decimalDigits: 0).format(n);
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
            style: _cellTextStyle(context),
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
      style: _cellTextStyle(context),
      textAlign: TextAlign.center,
    );
  }

  late final ProductsPricing productsPricing;

  double tableHeight = 0;
  final double tableRowHeight = 52;
  final double extraHeight = 85;
  final double footerExpandedHeight = 135;
  final double heightToAddWhenFooterIsExpanded = 110;
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
    super.initState();
    widget.controller.textSizeNotifier.addListener(_onTextSizeChanged);
    discount = widget.controller.discount;
    if (widget.controller.invoice?.currency case String currency) {
      selectedPriceCategory = (currency: currency, name: null);
    }
  }

  void _onTextSizeChanged() {
    setState(() {});
  }

  VoidCallback? _editingListener;

  @override
  void dispose() {
    widget.controller.textSizeNotifier.removeListener(_onTextSizeChanged);
    if (_editingListener != null) {
      widget.controller.enableEditingNotifier.removeListener(_editingListener!);
    }
    _debounce?.cancel();
    super.dispose();
  }

  bool _depsInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Column titles need l10n (an inherited widget), which is illegal in
    // initState. Build once here; later dependency changes (e.g. theme)
    // must not rebuild columns or grid state would reset.
    if (_depsInitialized) return;
    _depsInitialized = true;
    columns = [
      TrinaColumn(
        title: context.l10n.productModel,
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
        title: context.l10n.productDescription,
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
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              border: BorderDirectional(
                end: BorderSide(color: context.colorScheme.outlineVariant),
              ),
            ),
            child: Text(
              context.l10n.thankYouNote,
              style: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: BrandFonts.arabic,
                fontFamilyFallback: [],
              ),
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
        title: context.l10n.quantity,
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
            style: _cellTextStyle(context),
            textAlign: TextAlign.center,
          );
        },
        titleTextAlign: TrinaColumnTextAlign.center,
        title: context.l10n.unitPrice,
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
            padding: EdgeInsets.only(left: AppGaps.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  discount > 0 ? context.l10n.subtotal : context.l10n.total,
                  style: _smallLabelStyle(context),
                ),
                if (discount > 0 || widget.controller.editingIsEnabled) ...[
                  SizedBox(height: AppGaps.sm),
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
                                vertical: AppGaps.sm,
                                horizontal: AppGaps.md,
                              ),
                              child: TextFormField(
                                autofocus: true,
                                initialValue: discount > 0
                                    ? discount.toString()
                                    : null,
                                style: _cellTextStyle(context),

                                onFieldSubmitted: (value) {
                                  Navigator.of(context).pop();
                                  setState(() {
                                    discount =
                                        parseCanonicalDecimal(
                                          value,
                                        )?.toDouble() ??
                                        0;
                                  });
                                  widget.controller.discount = discount;
                                  // Discount-only edits must latch: saveToDB
                                  // writes only when dirty, otherwise Save
                                  // silently skips and the value is lost.
                                  widget.controller.hasUnsavedChanges = true;
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                    child: Text(
                      context.l10n.discount,
                      style: _smallLabelStyle(
                        context,
                      ).copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
                  SizedBox(height: AppGaps.sm),
                  Text('${context.l10n.total}:'),
                ],
              ],
            ),
          );
        },
      ),
      TrinaColumn(
        enableContextMenu: false,
        enableDropToResize: false,
        renderer: _cellRenderer,
        titleTextAlign: TrinaColumnTextAlign.center,
        textAlign: TrinaColumnTextAlign.center,
        title: context.l10n.lineTotal,
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
                  numberFormat: NumberFormat.currency(
                    locale: getNumberFormat().locale,
                    decimalDigits: getNumberFormat().decimalDigits,
                    symbol: getNumberFormat().currencySymbol,
                  ),
                  titleSpanBuilder: (sumValue) {
                    final numberFormat = getNumberFormat();
                    return [
                      WidgetSpan(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: AppGaps.sm,
                          children: [
                            Text(sumValue, style: _moneyStyle(context)),
                            if (discount > 0 ||
                                widget.controller.editingIsEnabled) ...[
                              Text(
                                '- ${numberFormat.format(discount)}',
                                style: _moneyStyle(context),
                              ),
                              Text(
                                numberFormat.format(
                                  getTotalWithDiscount(rendererContext),
                                ),
                                style: _moneyStyle(context),
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
          return IconButton(
            mouseCursor: SystemMouseCursors.click,
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
            icon: const Icon(Icons.add),
          );
        },
        titleRenderer: (rendererContext) {
          final style = _titleRendererStyle(context);
          return SizedBox(
            width: 200,
            height: 48,
            child: FittedBox(
              fit: BoxFit.fill,
              alignment: Alignment.center,
              child: Futuristic(
                autoStart: true,
                key: const Key('priceCategoryDropdown'),
                futureBuilder: () =>
                    GetIt.I.get<PricingCategoryRepo>().getAll(),
                dataBuilder: (context, categories) {
                  return DropdownButtonHideUnderline(
                    child: DropdownButton(
                      padding: EdgeInsets.zero,
                      icon: const SizedBox.shrink(),
                      value: selectedPriceCategory,
                      style: style,
                      hint: Text(context.l10n.selectPriceList),
                      items: [
                        DropdownMenuItem(
                          value: (currency: 'SP', name: null),
                          child: Text(
                            context.l10n.customPriceList('ل.س'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        DropdownMenuItem(
                          value: (currency: 'USD', name: null),
                          child: Text(
                            context.l10n.customPriceList('\$'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        ...categories.map(
                          (e) => DropdownMenuItem(
                            value: (currency: e.currency, name: e.name),
                            child: Text(
                              context.l10n.priceCategoryOption(
                                e.name,
                                e.currency,
                              ),
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
      child: Builder(
        builder: (context) {
          return TrinaGrid(
            configuration: TrinaGridConfiguration(
              enterKeyAction: TrinaGridEnterKeyAction.editingAndMoveRight,
              columnSize: TrinaGridColumnSizeConfig(
                autoSizeMode: TrinaAutoSizeMode.scale,
              ),
              enableMoveHorizontalInEditing: true,
              style: TrinaGridStyleConfig(
                rowHeight: tableRowHeight,
                cellDirtyColor: AppColors.dirtyCell,
                cellTextStyle: _cellTextStyle(context),
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
              _editingListener = () {
                final isEditing = widget.controller.editingIsEnabled;
                stateManager.hideColumn(columns.last, !isEditing);
                if (isEditing) {
                  onEnableEditing();
                } else {
                  onDisableEditing();
                }
              };
              widget.controller.enableEditingNotifier.addListener(
                _editingListener!,
              );

              stateManager.setShowColumnFilter(false);
            },
          );
        },
      ),
    );
  }

  void _updateControllerLines() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.controller.hasUnsavedChanges = true;
      // Carry sizes across desktop edits: the grid has no size cell, so a
      // rebuilt row inherits its product's previous size. Single-size lines
      // (and all legacy data) round-trip exactly; two sizes of the same
      // product edited here collapse onto the first size — set those sizes
      // on mobile instead.
      final prevByProduct = <int, InvoiceTableRow>{};
      for (final l in widget.controller.invoiceLines) {
        prevByProduct.putIfAbsent(l.product.id, () => l);
      }
      final invoiceRows = <InvoiceTableRow>[];
      for (var row in stateManager.refRows) {
        if (row.cells['id']!.value case String model) {
          final product = products[model]!;
          invoiceRows.add(
            InvoiceTableRow(
              unitPrice: row.cells['unit_price']!.value,
              product: product,
              amount: row.cells['amount']!.value,
              size: prevByProduct[product.id]?.size,
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
