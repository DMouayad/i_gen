import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get_it/get_it.dart';

import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/cart_bar.dart';
import 'package:i_gen/widgets/cart_sheet.dart';
import 'package:i_gen/widgets/invoice_discount_footer.dart';
import 'package:i_gen/widgets/prevent_pop.dart';
import 'package:i_gen/widgets/price_category_dropdown.dart';
import 'package:i_gen/widgets/product_grid.dart';

class InvoiceDetailsMobile extends StatefulWidget {
  const InvoiceDetailsMobile({
    super.key,
    required this.controller,
    this.onSaved,
  });

  final InvoiceDetailsController controller;
  final void Function(Invoice invoice)? onSaved;

  @override
  State<InvoiceDetailsMobile> createState() => _InvoiceDetailsMobileState();
}

class _InvoiceDetailsMobileState extends State<InvoiceDetailsMobile> {
  InvoiceDetailsController get controller => widget.controller;
  void Function(Invoice invoice)? get onSaved => widget.onSaved;

  @override
  void initState() {
    super.initState();
    controller.loadPricing().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<bool> _onSave(BuildContext context) async {
    try {
      await controller.saveToDB(disableEditing: false);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.unexpectedError(e.toString()))),
        );
      }
      return false;
    }
    if (controller.invoice != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.invoiceSaved(controller.total))),
        );
      }
      onSaved?.call(controller.invoice!);
    }
    return true;
  }

  Future<void> _openPreview(BuildContext context) async {
    if (!await _onSave(context)) return;
    if (!context.mounted) return;
    final wasEditing = controller.editingIsEnabled;
    controller.enableEditing = false;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InvoiceDetails(invoiceController: controller),
        ),
      );
    } finally {
      controller.enableEditing = wasEditing;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PreventPop(
      controller: controller,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            controller.invoice == null
                ? context.l10n.newInvoice
                : '#${controller.invoice!.id}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
          actions: [
            ValueListenableBuilder(
              valueListenable: controller.priceCategoryNotifier,
              builder: (context, category, _) => ListenableBuilder(
                listenable: controller.cart,
                builder: (context, _) => Center(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: Text(
                      '${controller.formatNumber(controller.cart.total)} ${category.currency}',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Customer + date + price-list chip, flattened from the old card.
            _HeaderSection(controller: controller),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder(
                valueListenable: controller.priceCategoryNotifier,
                builder: (context, _, _) => ProductGrid(
                  products: GetIt.I
                      .get<ProductsController>()
                      .products
                      .values
                      .toList(),
                  cart: controller.cart,
                  priceOf: controller.priceOf,
                  priceListenable: controller.priceCategoryNotifier,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: ValueListenableBuilder(
          valueListenable: controller.priceCategoryNotifier,
          builder: (context, category, _) => CartBar(
            cart: controller.cart,
            onOpenCart: () => showCartSheet(
              context,
              cart: controller.cart,
              showPrices: true,
              formatNumber: controller.formatNumber,
              currency: category.currency,
              footer: InvoiceDiscountFooter(controller: controller),
            ),
            onPreview: () => _openPreview(context),
            onSave: () => _onSave(context),
          ),
        ),
      ),
    );
  }
}

class _HeaderSection extends StatelessWidget {
  const _HeaderSection({required this.controller});
  final InvoiceDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          TypeAheadField<String>(
            controller: controller.customerNameController,
            itemBuilder: (context, value) => ListTile(
              dense: true,
              title: Text(value, style: context.textTheme.bodyMedium),
            ),
            onSelected: (value) => controller.customerName = value,
            builder: (context, textController, focusNode) {
              return TextFormField(
                controller: textController,
                focusNode: focusNode,
                onFieldSubmitted: (value) => controller.customerName = value,
                style: context.textTheme.bodyLarge,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: context.l10n.customerNameHint,
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                ),
              );
            },
            hideOnSelect: true,
            hideOnEmpty: false,
            emptyBuilder: (_) => const SizedBox.shrink(),
            suggestionsCallback: (query) async {
              final names = await GetIt.I.get<CustomerRepo>().search(query);
              if (query.isEmpty) return names.take(6).toList();
              return names;
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: .spaceBetween,
            children: [
              SizedBox(
                width: 150,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  onTap: () async {
                    final newDate = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2050),
                      initialDate: controller.invoiceDateNotifier.value,
                    );
                    if (newDate != null) {
                      controller.invoiceDateNotifier.value = newDate;
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: context.colorScheme.outlineVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    child: Row(
                      spacing: AppGaps.sm,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 16,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                        Flexible(
                          child: ValueListenableBuilder(
                            valueListenable: controller.invoiceDateNotifier,
                            builder: (context, value, _) {
                              return Text(
                                controller.getDate(),
                                style: context.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              );
                            },
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: controller.priceCategoryNotifier,
                builder: (context, category, _) => PriceCategoryDropdown(
                  priceCategory: category,
                  onCategoryChanged: (value) {
                    if (value != null) controller.switchPriceCategory(value);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
