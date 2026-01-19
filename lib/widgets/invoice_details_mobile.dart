import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_line_input_mobile.dart';

class InvoiceDetailsMobile extends StatelessWidget {
  const InvoiceDetailsMobile({super.key, required this.controller});
  final InvoiceDetailsController controller;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
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
              trailing: Icon(Icons.edit),
              leading: Icon(
                Icons.calendar_today_outlined,
                color: context.colorScheme.primary,
              ),
              title: ValueListenableBuilder(
                valueListenable: controller.invoiceDateNotifier,
                builder: (context, value, _) {
                  return Text(
                    controller.getDate(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colorScheme.surfaceContainerHighest.withOpacity(
                0.4,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.person, color: context.colorScheme.primary),
                const SizedBox(width: 8),
                SizedBox(
                  width: context.width * .7,
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
                      return Form(
                        key: controller.formKey,
                        child: TextFormField(
                          controller: textController,
                          focusNode: focusNode,
                          textAlign: TextAlign.center,
                          onFieldSubmitted: (value) {
                            controller.customerName = value;
                          },
                          style: context.defaultTextStyle.copyWith(
                            fontSize: 22,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Customer name',
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
    );
  }
}
