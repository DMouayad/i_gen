import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_details_mobile.dart';
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
  bool _isCapturing = false;

  Future<Uint8List> _capturePng([double pixelRation = 3.5]) async {
    await Future.delayed(const Duration(milliseconds: 100));
    RenderRepaintBoundary boundary =
        globalKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    ui.Image image = await boundary.toImage(pixelRatio: pixelRation);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();
    return pngBytes;
  }

  bool get _isDesktopPlatform =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;
  bool get _isMobilePlatform => Platform.isIOS || Platform.isAndroid;
  String _getInvoiceFileName() {
    return '${widget.invoiceController.invoiceId}_'
        '${widget.invoiceController.customerName}-'
        '${widget.invoiceController.getDate()}';
  }

  Future<void> saveAsImage() async {
    setState(() => _isCapturing = true);
    await Future.delayed(const Duration(milliseconds: 100));
    try {
      if (_isDesktopPlatform) {
        final directory = await getApplicationDocumentsDirectory();
        final file = await File(
          '${directory.path}/${_getInvoiceFileName()}.png',
        ).create();

        await file.writeAsBytes(await _capturePng());
      } else if (_isMobilePlatform) {
        final bool hasAccess = await Gal.hasAccess().then((hasAccess) {
          if (!hasAccess) {
            return Gal.requestAccess(toAlbum: true);
          }
          return true;
        });
        if (hasAccess) {
          Gal.putImageBytes(
            await _capturePng(),
            album: 'Invoices',
            name: _getInvoiceFileName(),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> saveAsPdf() async {
    setState(() => _isCapturing = true);
    await Future.delayed(const Duration(milliseconds: 100));
    try {
      final pngBytes = await _capturePng(5);
      final pdf = pw.Document();

      pdf.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(600, 700),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(pw.MemoryImage(pngBytes)),
            ); // Center
          },
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final file = await File(
        '${directory.path}/${_getInvoiceFileName()}.pdf',
      ).create();
      await file.writeAsBytes(await pdf.save());
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<bool?> _showUnsavedChangesDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Discard Changes?',
            style: TextStyle(fontSize: 20, color: context.colorScheme.error),
          ),
          content: const Text(
            'You have unsaved changes. Are you sure you want to discard them?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes, Discard'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filledBtnStyle = ButtonStyle(
      minimumSize: context.isMobile
          ? null
          : const WidgetStatePropertyAll(Size(130, 54)),
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontSize: context.isMobile ? 16 : 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    final invoiceContent = ValueListenableBuilder(
      valueListenable: widget.invoiceController.enableEditingNotifier,
      builder: (context, editingIsEnabled, _) {
        return IgnorePointer(
          ignoring: !editingIsEnabled,
          child: Container(
            color: Colors.white,
            constraints: BoxConstraints(
              maxWidth: editingIsEnabled ? 1200 : 920,
              minHeight: context.height,
            ),
            padding: context.isMobile
                ? const EdgeInsets.symmetric(horizontal: 20)
                : const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                _Header(widget.invoiceController),
                const SizedBox(height: 10),
                InvoiceCustomerInfo(widget.invoiceController),
                const SizedBox(height: 10),
                InvoiceTable(widget.invoiceController, onSaved: widget.onSaved),
                const SizedBox(height: 50),
              ],
            ),
          ),
        );
      },
    );

    final Widget bodyContent;

    if (_isCapturing || context.isMobile) {
      bodyContent = Flexible(
        child: RepaintBoundary(
          key: globalKey,
          child: FittedBox(child: invoiceContent),
        ),
      );
    } else {
      bodyContent = SingleChildScrollView(
        child: RepaintBoundary(key: globalKey, child: invoiceContent),
      );
    }

    return ValueListenableBuilder(
      valueListenable: widget.invoiceController.enableEditingNotifier,
      builder: (context, editingEnabled, _) {
        return PopScope(
          canPop:
              !editingEnabled || !widget.invoiceController.hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) {
              return;
            }
            final navigator = Navigator.of(context);
            final shouldPop = await _showUnsavedChangesDialog(context);
            if (shouldPop ?? false) {
              widget.invoiceController.hasUnsavedChanges = false;
              navigator.maybePop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              leadingWidth: 100,
              leading: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back),
                label: Text('Back', style: context.textTheme.titleMedium),
              ),
              actions: [
                SizedBox(
                  width: context.width * .8,
                  child: AnimatedCrossFade(
                    firstChild: Container(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.icon(
                        onPressed: () {
                          if (widget.invoiceController.hasUnsavedChanges) {
                            widget.invoiceController.enableEditing = false;
                            widget.invoiceController.hasUnsavedChanges = false;
                          }
                        },
                        label: const Text('Save'),
                        icon: const Icon(Icons.save),
                        style: filledBtnStyle,
                      ),
                    ),
                    secondChild: Row(
                      spacing: context.isMobile ? 0 : 4,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // if (!context.isMobile)
                        //   ValueListenableBuilder(
                        //     valueListenable:
                        //         widget.invoiceController.textSizeNotifier,
                        //     builder: (context, value, _) {
                        //       return Row(
                        //         children: [
                        //           Text(
                        //             "Text Size is ${value.floor()}",
                        //             style: TextStyle(fontSize: 18),
                        //           ),
                        //           Slider(
                        //             min: 16,
                        //             max: 28,
                        //             value: value.toDouble(),
                        //             onChanged: (value) {
                        //               widget
                        //                   .invoiceController
                        //                   .textSizeNotifier
                        //                   .value = value
                        //                   .floor();
                        //             },
                        //           ),
                        //         ],
                        //       );
                        //     },
                        //   ),
                        TextButton.icon(
                          onPressed: () {
                            widget.invoiceController.enableEditing = true;
                            widget.invoiceController.hasUnsavedChanges = true;
                          },
                          label: Text('Edit'),
                          icon: const Icon(Icons.edit),
                          style: filledBtnStyle,
                        ),
                        TextButton.icon(
                          onPressed: saveAsImage,
                          label: const Text('Image'),
                          icon: const Icon(Icons.image),
                          style: filledBtnStyle,
                        ),
                        TextButton.icon(
                          onPressed: saveAsPdf,
                          label: const Text('PDF'),
                          icon: const Icon(Icons.file_open_rounded),
                          style: filledBtnStyle,
                        ),
                      ],
                    ),
                    crossFadeState: editingEnabled
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    duration: const Duration(milliseconds: 300),
                  ),
                ),
              ],
            ),
            body: editingEnabled && context.isMobile
                ? InvoiceDetailsMobile(controller: widget.invoiceController)
                : Center(child: bodyContent),
          ),
        );
      },
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
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Image.asset('assets/l2.png', width: 330),
          ),
        ),
        Flexible(
          child: Column(
            children: [
              Text(
                "INVOICE",
                textAlign: TextAlign.end,
                style: context.textTheme.titleMedium?.copyWith(
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
