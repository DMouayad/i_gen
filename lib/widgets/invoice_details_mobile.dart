import 'package:flutter/material.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/widgets/invoice_screen/invoice_customer_info.dart';
import 'package:i_gen/widgets/invoice_line_input_mobile.dart';

class InvoiceDetailsMobile extends StatelessWidget {
  const InvoiceDetailsMobile({super.key, required this.controller});
  final InvoiceDetailsController controller;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          ListTile(
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
            leading: Text('Date: '),
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
          InvoiceCustomerInfo(controller, verticalPadding: 10),
          InvoiceLineInputMobile(controller: controller),
        ],
      ),
    );
  }
}
