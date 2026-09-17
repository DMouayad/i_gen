import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/order_by.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_details_mobile.dart';
import 'package:i_gen/widgets/sync_button.dart';
import 'package:intl/intl.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.onLoaded});
  final void Function(InvoiceDetailsController invoiceController) onLoaded;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

typedef SortItem = (String, OrderBy?);

class _ArchiveScreenState extends State<ArchiveScreen> {
  List<Invoice> invoices = [];
  bool isLoading = false;
  Object? loadError;
  OrderBy? orderBy = OrderBy('date', false);

  Future<void> _load() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });
    try {
      invoices = await GetIt.I.get<InvoiceRepo>().getInvoices(orderBy);
    } catch (e) {
      loadError = e;
    }
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  void handleOnSorted() async {
    await _load();
  }

  /// Pull-to-refresh: run a sync, then reload invoices from the repo.
  Future<void> _refresh() async {
    await SyncTrigger.instance.syncNow();
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 1024),
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: AppGaps.xl),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppGaps.md),
                child: OverflowBar(
                  alignment: MainAxisAlignment.start,
                  children: [
                    Text(context.l10n.sortLabel),
                    const SizedBox(width: AppGaps.sm),
                    DropdownButton<OrderBy?>(
                      value: orderBy,
                      hint: Text(context.l10n.sortLabel),
                      items: [
                        DropdownMenuItem(
                          value: OrderBy('customer', true),
                          child: Text(context.l10n.sortAz),
                        ),
                        DropdownMenuItem(
                          value: OrderBy('customer', false),
                          child: Text(context.l10n.sortZa),
                        ),
                        DropdownMenuItem(
                          value: OrderBy('date', false),
                          child: Text(context.l10n.sortNewest),
                        ),
                        DropdownMenuItem(
                          value: OrderBy('date', true),
                          child: Text(context.l10n.sortOldest),
                        ),
                        DropdownMenuItem(
                          value: null,
                          child: Text(context.l10n.sortNone),
                        ),
                      ],
                      onChanged: (value) async {
                        orderBy = value;
                        handleOnSorted();
                      },
                    ),
                    SyncButton(onSynced: _load),
                  ],
                ),
              ),

              (isLoading)
                  ? const CircularProgressIndicator()
                  : (loadError != null)
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n.unexpectedError(loadError.toString()),
                        ),
                        const SizedBox(height: AppGaps.sm),
                        OutlinedButton(
                          style: const ButtonStyle(
                            minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                          ),
                          onPressed: _load,
                          child: Text(context.l10n.retry),
                        ),
                      ],
                    )
                  : invoices.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(AppGaps.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.archive_outlined,
                            size: 48,
                            color: context.colorScheme.outline,
                          ),
                          const SizedBox(height: AppGaps.sm),
                          Text(
                            context.l10n.noInvoicesFound,
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: AppGaps.sm),
                          Text(
                            context.l10n.archiveEmptyHint,
                            textAlign: TextAlign.center,
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: context.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(AppGaps.md),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: invoices.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AppGaps.sm),
                        itemBuilder: (context, index) => _Item(
                          invoice: invoices[index],
                          onInvoiceSelected: (invoiceController) {
                            widget.onLoaded(invoiceController);
                          },
                          onSaved: (newInvoice) {
                            setState(() => invoices[index] = newInvoice);
                          },
                          onDeleted: () {
                            setState(() {
                              invoices.remove(invoices[index]);
                            });
                          },
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final Invoice invoice;
  final void Function(InvoiceDetailsController invoiceController)
  onInvoiceSelected;
  final VoidCallback onDeleted;
  final void Function(Invoice newInvoice) onSaved;

  const _Item({
    required this.invoice,
    required this.onInvoiceSelected,
    required this.onDeleted,
    required this.onSaved,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colorScheme.surface,
      child: ListTile(
        shape: RoundedRectangleBorder(
          side: BorderSide(color: context.colorScheme.surfaceDim),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: AppGaps.sm,
          horizontal: AppGaps.md,
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) {
                final invoiceController = InvoiceDetailsController(invoice);
                onInvoiceSelected(invoiceController);
                invoiceController.enableEditing = true;
                return context.isMobile
                    ? InvoiceDetailsMobile(
                        controller: invoiceController,
                        onSaved: onSaved,
                      )
                    : InvoiceDetails(
                        invoiceController: invoiceController,
                        onSaved: onSaved,
                      );
              },
            ),
          );
        },
        title: Text(
          invoice.customerName,
          style: context.textTheme.titleLarge?.copyWith(
            color: context.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              DateFormat.yMd().format(invoice.date),
              style: context.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            IconButton(
              tooltip: context.l10n.delete,
              color: context.colorScheme.error,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.dialog),
                    ),
                    title: Text(context.l10n.deleteConfirmTitle),
                    content: Text(context.l10n.deleteConfirmMessage),
                    actions: [
                      TextButton(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(context.l10n.cancelButton),
                      ),
                      FilledButton(
                        style: const ButtonStyle(
                          minimumSize: WidgetStatePropertyAll(Size(64, 48)),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(context.l10n.delete),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
                await GetIt.I.get<InvoiceRepo>().delete(invoice);
                onDeleted();
              },
            ),
          ],
        ),
        dense: false,
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppGaps.xs),
          child: Text(
            invoice.lines
                .map((e) => '${e.product.model}:${e.amount}')
                .toList()
                .join('   '),
          ),
        ),
      ),
    );
  }
}
