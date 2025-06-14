import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/order_by.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
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
  OrderBy? orderBy = OrderBy('date', false);

  void handleOnSorted() async {
    if (orderBy != null) {
      invoices = await GetIt.I.get<InvoiceRepo>().getInvoices(orderBy);
      setState(() {});
    }
  }

  @override
  void initState() {
    setState(() {
      isLoading = true;
    });
    GetIt.I.get<InvoiceRepo>().getInvoices(orderBy).then((items) {
      invoices = items;
      setState(() {
        isLoading = false;
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      onDidRemovePage: (page) {},
      pages: [
        MaterialPage(
          name: '/',
          child: Container(
            constraints: BoxConstraints(maxWidth: 1024),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(top: 30),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: OverflowBar(
                      alignment: MainAxisAlignment.start,
                      children: [
                        Text('SORT'),
                        SizedBox(width: 10),
                        DropdownButton<OrderBy?>(
                          value: orderBy,
                          hint: Text('Sort'),
                          items: [
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
                      ? CircularProgressIndicator()
                      : invoices.isEmpty
                      ? Text('No invoices found')
                      : Container(
                          padding: EdgeInsets.symmetric(vertical: 50),
                          height: context.height,
                          width: 1000,
                          child: ListView.separated(
                            itemCount: invoices.length,
                            separatorBuilder: (context, index) =>
                                SizedBox(height: 5),
                            itemBuilder: (context, index) => _Item(
                              invoice: invoices[index],
                              onInvoiceSelected: (invoiceController) {
                                widget.onLoaded(invoiceController);
                              },
                              onSaved: (newInvoice) {
                                setState(() {
                                  invoices[index] = newInvoice;
                                });
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
        ),
      ],
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
          borderRadius: BorderRadius.circular(4),
        ),
        contentPadding: EdgeInsets.symmetric(vertical: 7, horizontal: 20),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) {
                final invoiceController = InvoiceDetailsController(invoice);
                onInvoiceSelected(invoiceController);
                return InvoiceDetails(
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
                label: Text('Delete', style: TextStyle(color: Colors.red)),
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
