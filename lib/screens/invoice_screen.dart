import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_screen/invoice_btns.dart';
import 'package:i_gen/widgets/invoice_screen/invoice_customer_info.dart';
import 'package:i_gen/widgets/invoice_table.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class InvoiceDetails extends StatefulWidget {
  const InvoiceDetails({
    super.key,
    required this.invoiceController,
    this.onSaved,
  });
  final InvoiceDetailsController invoiceController;
  final void Function(Invoice newInvoice)? onSaved;

  @override
  State<InvoiceDetails> createState() => _InvoiceDetailsState();
}

class _InvoiceDetailsState extends State<InvoiceDetails> {
  GlobalKey globalKey = GlobalKey();

  Future<Uint8List> _capturePng([double pixelRation = 3]) async {
    await Future.delayed(Duration(milliseconds: 100));
    RenderRepaintBoundary boundary =
        globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    ui.Image image = await boundary.toImage(pixelRatio: pixelRation);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();
    return pngBytes;
  }

  Future<void> saveAsImage() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = await File('${directory.path}/image.png').create();

    await file.writeAsBytes(await _capturePng());
  }

  Future<void> saveAsPdf() async {
    final pngBytes = await _capturePng(5);
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(600, 700),
        build: (pw.Context context) {
          return pw.Center(child: pw.Image(pw.MemoryImage(pngBytes))); // Center
        },
      ),
    );

    final directory = await getApplicationDocumentsDirectory();
    final file = await File('${directory.path}/image1.pdf').create();
    await file.writeAsBytes(await pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),

            child: SingleChildScrollView(
              child: RepaintBoundary(
                key: globalKey,
                child: ValueListenableBuilder(
                  valueListenable:
                      widget.invoiceController.enableEditingNotifier,
                  builder: (context, editingIsEnabled, _) {
                    return IgnorePointer(
                      ignoring: !editingIsEnabled,
                      child: Container(
                        color: Colors.white,
                        constraints: BoxConstraints(
                          maxWidth: editingIsEnabled ? double.infinity : 920,
                          minHeight: context.height,
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          children: [
                            _Header(widget.invoiceController),
                            SizedBox(height: 10),
                            InvoiceCustomerInfo(widget.invoiceController),
                            SizedBox(height: 10),

                            InvoiceTable(
                              widget.invoiceController,
                              onSaved: widget.onSaved,
                            ),
                            SizedBox(height: 50),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Container(
          constraints: BoxConstraints.expand(width: 200),
          alignment: Alignment.centerRight,
          // color: Colors.red,
          child: InvoiceBtns(
            controller: widget.invoiceController,
            onExportAsImage: saveAsImage,
            onExportAsPdf: saveAsPdf,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.controller);

  final InvoiceDetailsController controller;
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/l2.png', width: 330),
        ),
        Column(
          children: [
            Text(
              "INVOICE",
              textAlign: TextAlign.end,
              style: context.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final newDate = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2050),
                );
                if (newDate != null) {
                  controller.invoiceDateNotifier.value = newDate;
                }
              },
              child: ValueListenableBuilder(
                valueListenable: controller.invoiceDateNotifier,
                builder: (context, value, _) {
                  return Text(
                    controller.getDate(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
