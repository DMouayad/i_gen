import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/controllers/invoices_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/order_by.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_details_mobile.dart';
import 'package:intl/intl.dart';

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key, required this.onLoaded});
  final void Function(InvoiceDetailsController invoiceController) onLoaded;

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

typedef SortItem = (String, OrderBy?);

class _ArchiveScreenState extends State<ArchiveScreen> {
  InvoicesController get controller => GetIt.I.get();

  bool isLoading = false;
  OrderBy? orderBy = OrderBy('date', false);

  void handleOnSorted() async {
    if (orderBy != null) {
      final invoices = await GetIt.I.get<InvoiceRepo>().getInvoices(orderBy);
      controller.update(invoices);
    }
  }

  @override
  void initState() {
    setState(() {
      isLoading = true;
    });
    GetIt.I.get<InvoiceRepo>().getInvoices(orderBy).then((items) {
      controller.update(items);
      setState(() {
        isLoading = false;
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: 1024),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 30),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: OverflowBar(
                alignment: MainAxisAlignment.start,
                children: [
                  const Text('SORT'),
                  const SizedBox(width: 10),
                  DropdownButton<OrderBy?>(
                    value: orderBy,
                    hint: const Text('Sort'),
                    items: const [
                      DropdownMenuItem(
                        value: OrderBy('customer', true),
                        child: Text('From A-Z'),
                      ),
                      DropdownMenuItem(
                        value: OrderBy('customer', false),
                        child: Text('From Z-A'),
                      ),
                      DropdownMenuItem(
                        value: OrderBy('date', false),
                        child: Text('From Newest'),
                      ),
                      DropdownMenuItem(
                        value: OrderBy('date', true),
                        child: Text('From Oldest'),
                      ),
                      DropdownMenuItem(value: null, child: Text('None')),
                    ],
                    onChanged: (value) async {
                      if (value != null) {
                        orderBy = value;
                        handleOnSorted();
                      }
                    },
                  ),
                ],
              ),
            ),

            (isLoading)
                ? const CircularProgressIndicator()
                : ListenableBuilder(
                    listenable: controller,
                    builder: (context, child) {
                      final invoices = controller.invoices;
                      return invoices.isEmpty
                          ? const Text('No invoices found')
                          : Container(
                              padding: const EdgeInsets.symmetric(vertical: 50),
                              height: context.height,
                              width: 1000,
                              child: ListView.separated(
                                itemCount: invoices.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 5),
                                itemBuilder: (context, index) => _Item(
                                  key: ValueKey(invoices[index].id),
                                  invoice: invoices[index],
                                  onInvoiceSelected: (invoiceController) {
                                    widget.onLoaded(invoiceController);
                                  },
                                  onSaved: controller.updateInvoice,
                                  onDeleted: () =>
                                      controller.removeInvoice(invoices[index]),
                                ),
                              ),
                            );
                    },
                  ),
          ],
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
    super.key,
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
          borderRadius: BorderRadius.circular(4),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
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
        trailing: SizedBox(
          width: 150,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat.yMd().format(invoice.date),
                style: context.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await GetIt.I.get<InvoiceRepo>().delete(invoice);
                  onDeleted();
                },
                label: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
        dense: false,
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5.0),
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
