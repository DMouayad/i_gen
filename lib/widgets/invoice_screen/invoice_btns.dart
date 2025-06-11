import 'package:flutter/material.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/utils/context_extensions.dart';

class InvoiceBtns extends StatelessWidget {
  const InvoiceBtns({
    super.key,
    required this.controller,
    required this.onExportAsImage,
    required this.onExportAsPdf,
  });
  final InvoiceDetailsController controller;
  final VoidCallback onExportAsImage;
  final VoidCallback onExportAsPdf;
  @override
  Widget build(BuildContext context) {
    final filledBtnStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(120, 54)),
      textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 18)),
    );

    return ValueListenableBuilder(
      valueListenable: controller.enableEditingNotifier,
      builder: (context, editingEnabled, _) {
        return AnimatedCrossFade(
          firstChild: OverflowBar(
            alignment: MainAxisAlignment.center,
            overflowAlignment: OverflowBarAlignment.center,
            spacing: 10,
            overflowSpacing: 30,
            children: [
              if (Navigator.of(context).canPop())
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: filledBtnStyle,
                  child: Text('Go back'),
                ),
              FilledButton.icon(
                onPressed: () {
                  if (controller.hasUnsavedChanges) {
                    controller.enableEditing = false;
                    controller.hasUnsavedChanges = false;
                  }
                },
                label: Text('Save'),
                icon: Icon(Icons.save),
                style: filledBtnStyle,
              ),
            ],
          ),
          secondChild: OverflowBar(
            alignment: MainAxisAlignment.center,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 10,
            overflowSpacing: 30,
            children: [
              if (Navigator.of(context).canPop())
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: filledBtnStyle,
                  child: Text('Go back'),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  controller.enableEditing = true;
                  controller.hasUnsavedChanges = true;
                },
                label: Text('Edit', style: context.defaultTextStyle),
                icon: Icon(Icons.edit),
                style: filledBtnStyle,
              ),

              FilledButton.icon(
                onPressed: onExportAsImage,
                label: Text('Export As Image'),
                icon: Icon(Icons.image),
                style: filledBtnStyle,
              ),
              FilledButton.icon(
                onPressed: onExportAsPdf,
                label: Text('Export As PDF'),
                icon: Icon(Icons.file_open_rounded),
                style: filledBtnStyle,
              ),
            ],
          ),
          crossFadeState:
              editingEnabled
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
          duration: Duration(milliseconds: 300),
        );
      },
    );
  }
}
