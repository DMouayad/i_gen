import 'package:flutter/material.dart';

import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get_it/get_it.dart';

import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/screens/invoice_screen.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_line_input_mobile.dart';
import 'package:i_gen/widgets/prevent_pop.dart';

class InvoiceDetailsMobile extends StatelessWidget {
  const InvoiceDetailsMobile({
    super.key,
    required this.controller,
    this.onSaved,
  });
  final InvoiceDetailsController controller;
  final void Function(Invoice invoice)? onSaved;

  @override
  Widget build(BuildContext context) {
    final btnTextStyle = context.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );
    return PreventPop(
      controller: controller,
      child: Scaffold(
        appBar: AppBar(
          title: controller.invoice == null ? const Text('New invoice') : null,
          actions: [
            TextButton.icon(
              onPressed: () async {
                await controller.saveToDB(disableEditing: false);
                if (controller.invoice != null) {
                  onSaved?.call(controller.invoice!);
                }
              },
              icon: const Icon(Icons.save, size: 22),
              label: Text('Save', style: btnTextStyle),
            ),
            TextButton.icon(
              onPressed: () {
                controller.saveToDB();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        InvoiceDetails(invoiceController: controller),
                  ),
                );
              },
              icon: const Icon(Icons.preview, size: 22),
              label: Text('Preview', style: btnTextStyle),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 30),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 250,
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tileColor: context.colorScheme.surfaceContainerHighest
                            .withOpacity(0.4),
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
                        trailing: const Icon(Icons.edit),
                        leading: Icon(
                          Icons.calendar_today_outlined,
                          color: context.colorScheme.primary,
                        ),
                        title: ValueListenableBuilder(
                          valueListenable: controller.invoiceDateNotifier,
                          builder: (context, value, _) {
                            return Text(
                              controller.getDate(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: context.colorScheme.surfaceContainerHighest
                          .withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    margin: const EdgeInsets.all(8.0),
                    padding: const EdgeInsets.all(8.0),
                    child: ValueListenableBuilder(
                      valueListenable: controller.totalNotifier,
                      builder: (context, value, _) {
                        return Text(
                          'Grand total: $value',
                          style: context.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest
                      .withOpacity(0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person, color: context.colorScheme.primary),
                    const SizedBox(width: 8),
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
                            textAlign: TextAlign.center,
                            onFieldSubmitted: (value) {
                              controller.customerName = value;
                            },
                            style: context.defaultTextStyle.copyWith(
                              fontSize: 20,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Customer name',
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  width: 1,
                                  color: context.colorScheme.outline,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  width: 2,
                                  color: context.colorScheme.primary,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );
                        },
                        hideOnSelect: true,
                        hideOnEmpty: true,
                        suggestionsCallback: (query) =>
                            GetIt.I.get<CustomerRepo>().search(query),
                      ),
                    ),
                  ],
                ),
              ),
              InvoiceLineInputMobile(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}
