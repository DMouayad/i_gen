import 'package:flutter/material.dart';

import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';

import 'package:i_gen/constants.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_line_input_mobile.dart';
import 'package:i_gen/widgets/prevent_pop.dart';
import 'package:i_gen/widgets/sync_spinner.dart';

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
  VoidCallback? _addLine;

  InvoiceDetailsController get controller => widget.controller;
  void Function(Invoice invoice)? get onSaved => widget.onSaved;

  /// Saves and reports whether it succeeded. Callers must not navigate
  /// (e.g. to preview) when this returns false.
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

  @override
  Widget build(BuildContext context) {
    final btnTextStyle = context.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return PreventPop(
      controller: controller,
      child: Scaffold(
        appBar: AppBar(
          title: controller.invoice == null
              ? Text(context.l10n.newInvoice)
              : null,
          actions: [
            const SyncSpinner(),
            TextButton.icon(
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size(64, 48)),
              ),
              onPressed: () async {
                if (!await _onSave(context)) return;
                if (!context.mounted) return;
                // Preview is readonly: park editing, restore the previous
                // state on return (a readonly opener must stay readonly).
                final wasEditing = controller.editingIsEnabled;
                controller.enableEditing = false;
                try {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          InvoiceDetails(invoiceController: controller),
                    ),
                  );
                } finally {
                  controller.enableEditing = wasEditing;
                }
              },
              icon: const Icon(Icons.preview, size: 22),
              label: Text(context.l10n.previewButton, style: btnTextStyle),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            children: [
              // Hero: who this invoice is for, plus when. Customer first
              // (F-pattern), date as a compact row in the same card.
              Container(
                margin: const EdgeInsets.all(AppGaps.sm),
                padding: const EdgeInsets.all(AppGaps.md),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          color: context.colorScheme.primary,
                        ),
                        const SizedBox(width: AppGaps.sm),
                        Flexible(
                          child: TypeAheadField<String>(
                            controller: controller.customerNameController,
                            itemBuilder: (context, value) => ListTile(
                              title: Text(
                                value,
                                style: context.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              tileColor: context.colorScheme.surface,
                            ),
                            onSelected: (value) {
                              controller.customerName = value;
                            },
                            builder: (context, textController, focusNode) {
                              return TextFormField(
                                controller: textController,
                                focusNode: focusNode,
                                onFieldSubmitted: (value) {
                                  controller.customerName = value;
                                },
                                style: context.defaultTextStyle,
                                decoration: InputDecoration(
                                  labelText: context.l10n.customerNameHint,
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      width: 1,
                                      color: context.colorScheme.outline,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.control,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      width: 2,
                                      color: context.colorScheme.primary,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.control,
                                    ),
                                  ),
                                ),
                              );
                            },
                            hideOnSelect: true,
                            hideOnEmpty: false,
                            emptyBuilder: (_) => const SizedBox.shrink(),
                            suggestionsCallback: (query) async {
                              final names = await GetIt.I
                                  .get<CustomerRepo>()
                                  .search(query);
                              // Empty query: shortcut to past customers.
                              if (query.isEmpty) return names.take(6).toList();
                              return names;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppGaps.md),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadii.control),
                      onTap: () async {
                        final newDate = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2025),
                          lastDate: DateTime(2050),
                        );
                        if (newDate != null) {
                          controller.invoiceDateNotifier.value = newDate;
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppGaps.sm,
                          vertical: AppGaps.md,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 20,
                              color: context.colorScheme.primary,
                            ),
                            const SizedBox(width: AppGaps.md),
                            ValueListenableBuilder(
                              valueListenable: controller.invoiceDateNotifier,
                              builder: (context, value, _) {
                                return Text(
                                  controller.getDate(),
                                  style: context.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                );
                              },
                            ),
                            const Spacer(),
                            Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: context.colorScheme.outline,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InvoiceLineInputMobile(
                controller: controller,
                // Fires from the child's didChangeDependencies, i.e. during
                // the build phase: setState must be deferred post-frame or
                // the framework throws (ancestor dirtied while a descendant
                // like TypeAhead's RawGestureDetector is building).
                onAddLineChanged: (cb) {
                  if (_addLine == cb) return;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || _addLine == cb) return;
                    setState(() => _addLine = cb);
                  });
                },
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addLine,
          icon: const Icon(Icons.add),
          label: Text(context.l10n.addItem),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.all(AppGaps.md),
            decoration: BoxDecoration(
              color: context.colorScheme.surface,
              border: Border(
                top: BorderSide(color: context.colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: controller.totalNotifier,
                    builder: (context, value, _) {
                      final symbol =
                          currencies[controller.currency] ??
                          controller.currency;
                      final amount = NumberFormat.decimalPattern().format(
                        value,
                      );
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.total,
                            style: context.textTheme.labelMedium?.copyWith(
                              color: context.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.3),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: Text(
                              '$amount $symbol',
                              key: ValueKey(value),
                              style: context.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _onSave(context),
                  icon: const Icon(Icons.save),
                  label: Text(context.l10n.saveButton, style: btnTextStyle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
