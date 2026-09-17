import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:gal/gal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:i_gen/widgets/invoice_screen/invoice_customer_info.dart';
import 'package:i_gen/widgets/invoice_table.dart';
import 'package:i_gen/widgets/prevent_pop.dart';

/// Save/share target for the preview popup menus.
enum _ExportKind { image, pdf }

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

  Future<void> _save() async {
    await widget.invoiceController.saveToDB();
    if (widget.invoiceController.invoice != null) {
      widget.onSaved?.call(widget.invoiceController.invoice!);
    }
  }

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

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runExport(Future<void> Function() op) async {
    setState(() => _isCapturing = true);
    await Future.delayed(const Duration(milliseconds: 100));
    try {
      await op();
    } catch (e) {
      if (!mounted) return;
      _toast(context.l10n.unexpectedError(e.toString()));
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<Uint8List> _buildPdfBytes() async {
    final pngBytes = await _capturePng(5);
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(600, 700),
        build: (pw.Context context) {
          return pw.Center(child: pw.Image(pw.MemoryImage(pngBytes))); // Center
        },
      ),
    );
    return pdf.save();
  }

  Future<File> _writeTempFile(String name, Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _saveImage() {
    // Captured before the awaits: context may be gone when they complete.
    final l10n = context.l10n;
    return _runExport(() async {
      if (_isDesktopPlatform) {
        final directory = await getApplicationDocumentsDirectory();
        final file = await File(
          '${directory.path}/${_getInvoiceFileName()}.png',
        ).create();

        await file.writeAsBytes(await _capturePng());
        _toast(l10n.invoiceSavedToDocuments);
      } else if (_isMobilePlatform) {
        final bool hasAccess = await Gal.hasAccess().then((hasAccess) {
          if (!hasAccess) {
            return Gal.requestAccess(toAlbum: true);
          }
          return true;
        });
        if (hasAccess) {
          await Gal.putImageBytes(
            await _capturePng(),
            album: 'Invoices',
            name: _getInvoiceFileName(),
          );
          _toast(l10n.invoiceSavedToGallery);
        }
      }
    });
  }

  Future<void> _savePdf() {
    final l10n = context.l10n;
    return _runExport(() async {
      final directory = await getApplicationDocumentsDirectory();
      final file = await File(
        '${directory.path}/${_getInvoiceFileName()}.pdf',
      ).create();
      await file.writeAsBytes(await _buildPdfBytes());
      _toast(l10n.invoiceSavedToDocuments);
    });
  }

  Future<void> _shareFile(File file, String mimeType) async {
    final l10n = context.l10n;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        text: _getInvoiceFileName(),
      ),
    );
    if (result.status == ShareResultStatus.success) {
      _toast(l10n.invoiceShared);
    }
  }

  Future<void> _shareImage() => _runExport(() async {
    final file = await _writeTempFile(
      '${_getInvoiceFileName()}.png',
      await _capturePng(),
    );
    await _shareFile(file, 'image/png');
  });

  Future<void> _sharePdf() => _runExport(() async {
    final file = await _writeTempFile(
      '${_getInvoiceFileName()}.pdf',
      await _buildPdfBytes(),
    );
    await _shareFile(file, 'application/pdf');
  });

  /// Opens the image/PDF menu anchored under [buttonContext] and runs
  /// [onSelected]. A real button + [showMenu] instead of nesting a button
  /// inside a PopupMenuButton (the inner button would swallow the tap that
  /// opens the menu).
  Future<void> _selectExport(
    BuildContext buttonContext, {
    required String imageLabel,
    required String pdfLabel,
    required Future<void> Function(_ExportKind kind) onSelected,
  }) async {
    final box = buttonContext.findRenderObject()! as RenderBox;
    final anchor = box.localToGlobal(Offset.zero);
    final kind = await showMenu<_ExportKind>(
      context: buttonContext,
      position: RelativeRect.fromLTRB(
        anchor.dx,
        anchor.dy + box.size.height,
        anchor.dx + box.size.width,
        anchor.dy,
      ),
      items: [
        PopupMenuItem(
          value: _ExportKind.image,
          child: ListTile(
            leading: const Icon(Icons.image),
            title: Text(imageLabel),
          ),
        ),
        PopupMenuItem(
          value: _ExportKind.pdf,
          child: ListTile(
            leading: const Icon(Icons.file_open_rounded),
            title: Text(pdfLabel),
          ),
        ),
      ],
    );
    if (kind != null && mounted) {
      await onSelected(kind);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filledBtnStyle = ButtonStyle(
      minimumSize: context.isMobile
          ? null
          : const WidgetStatePropertyAll(Size(128, 56)),
      textStyle: WidgetStatePropertyAll(
        context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
              maxWidth: editingIsEnabled ? 1100 : 980,
              minHeight: context.height,
            ),
            padding: context.isMobile
                ? const EdgeInsets.symmetric(horizontal: AppGaps.md)
                : const EdgeInsets.symmetric(horizontal: AppGaps.xl),
            child: Column(
              children: [
                _Header(widget.invoiceController),
                const SizedBox(height: AppGaps.sm),
                InvoiceCustomerInfo(widget.invoiceController),
                const SizedBox(height: AppGaps.sm),
                // Desktop keeps the table editor (mobile uses the grid).
                InvoiceTable(widget.invoiceController),
                const SizedBox(height: AppGaps.xl + AppGaps.md),
              ],
            ),
          ),
        );
      },
    );

    final Widget bodyContent;

    if (_isCapturing || context.isMobile) {
      bodyContent = RepaintBoundary(
        key: globalKey,
        child: FittedBox(child: invoiceContent),
      );
    } else {
      bodyContent = SingleChildScrollView(
        child: RepaintBoundary(key: globalKey, child: invoiceContent),
      );
    }

    return PreventPop(
      controller: widget.invoiceController,
      child: ValueListenableBuilder(
        valueListenable: widget.invoiceController.enableEditingNotifier,
        builder: (context, editingEnabled, _) {
          return Scaffold(
            appBar: AppBar(
              actions: [
                SizedBox(
                  width: context.width * .8,
                  child: AnimatedCrossFade(
                    firstChild: Container(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton.icon(
                        onPressed: _save,
                        label: Text(context.l10n.save),
                        icon: const Icon(Icons.save),
                        style: filledBtnStyle,
                      ),
                    ),
                    secondChild: Row(
                      spacing: AppGaps.sm,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!context.isMobile)
                          TextButton.icon(
                            onPressed: () {
                              widget.invoiceController.enableEditing = true;
                            },
                            label: Text(context.l10n.edit),
                            icon: const Icon(Icons.edit),
                            style: filledBtnStyle,
                          ),
                        Builder(
                          builder: (buttonContext) => OutlinedButton(
                            onPressed: () => _selectExport(
                              buttonContext,
                              imageLabel: context.l10n.saveAsImage,
                              pdfLabel: context.l10n.saveAsPdf,
                              onSelected: (kind) {
                                switch (kind) {
                                  case _ExportKind.image:
                                    return _saveImage();
                                  case _ExportKind.pdf:
                                    return _savePdf();
                                }
                              },
                            ),
                            child: Text(context.l10n.save),
                          ),
                        ),
                        Builder(
                          builder: (buttonContext) => OutlinedButton(
                            onPressed: () => _selectExport(
                              buttonContext,
                              imageLabel: context.l10n.shareAsImage,
                              pdfLabel: context.l10n.shareAsPdf,
                              onSelected: (kind) {
                                switch (kind) {
                                  case _ExportKind.image:
                                    return _shareImage();
                                  case _ExportKind.pdf:
                                    return _sharePdf();
                                }
                              },
                            ),
                            child: Text(context.l10n.shareButton),
                          ),
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
            // Editing uses the table on desktop and the grid on mobile;
            // the paper above is preview/print only.
            body: Center(child: bodyContent),
          );
        },
      ),
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
            padding: const EdgeInsets.all(AppGaps.sm),
            child: Image.asset('assets/l2.png', width: 330),
          ),
        ),
        Flexible(
          child: Column(
            children: [
              Text(
                context.l10n.invoiceTitle,
                textAlign: TextAlign.end,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: AppGaps.sm),
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
                      style: context.textTheme.titleLarge?.copyWith(
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
