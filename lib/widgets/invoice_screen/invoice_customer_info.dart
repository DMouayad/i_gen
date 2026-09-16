import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/utils/context_extensions.dart';

class InvoiceCustomerInfo extends StatelessWidget {
  const InvoiceCustomerInfo(
    this.controller, {
    this.verticalPadding = AppGaps.xl,
    super.key,
  });

  final InvoiceDetailsController controller;
  final double verticalPadding;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppGaps.xs,
        vertical: verticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.colorScheme.surfaceDim),
              ),
            ),
            padding: const EdgeInsets.only(bottom: AppGaps.sm),
            alignment: Alignment.center,
            child: Text(context.l10n.billTo, style: context.defaultTextStyle),
          ),
          TypeAheadField<String>(
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

                  style: context.defaultTextStyle,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.circular(AppRadii.control),
                    ),
                    hintText: context.l10n.customerNameHint,
                  ),
                ),
              );
            },
            hideOnSelect: true,
            hideOnEmpty: true,

            suggestionsCallback: (query) =>
                GetIt.I.get<CustomerRepo>().search(query),
          ),
        ],
      ),
    );
  }
}
