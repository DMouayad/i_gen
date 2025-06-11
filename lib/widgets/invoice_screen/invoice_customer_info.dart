import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/utils/context_extensions.dart';

class InvoiceCustomerInfo extends StatelessWidget {
  const InvoiceCustomerInfo(this.controller, {super.key});

  final InvoiceDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 30),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.colorScheme.surfaceDim),
              ),
            ),
            padding: EdgeInsets.only(bottom: 10),
            alignment: Alignment.center,
            child: Text('BILL TO', style: context.defaultTextStyle),
          ),
          SizedBox(
            width: double.infinity,
            child: TypeAheadField<String>(
              controller: controller.customerNameController,
              itemBuilder:
                  (context, value) => ListTile(
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

                    style: context.defaultTextStyle.copyWith(fontSize: 22),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      hintText: 'Customer name',
                    ),
                  ),
                );
              },
              hideOnSelect: true,
              hideOnEmpty: true,

              suggestionsCallback:
                  (query) => GetIt.I.get<CustomerRepo>().search(query),
            ),
          ),
        ],
      ),
    );
  }
}
