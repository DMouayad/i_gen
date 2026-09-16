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
      minimumSize: const WidgetStatePropertyAll(Size(128, 56)),
      textStyle: WidgetStatePropertyAll(
        context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );

    return ValueListenableBuilder(
      valueListenable: controller.enableEditingNotifier,
      builder: (context, editingEnabled, _) {
        return AnimatedCrossFade(
          firstChild: OverflowBar(
            alignment: MainAxisAlignment.center,
            overflowAlignment: OverflowBarAlignment.center,
            spacing: AppGaps.sm,
            overflowSpacing: AppGaps.xl,
            children: [
              if (Navigator.of(context).canPop()) ...[
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: filledBtnStyle,
                  child: Text(context.l10n.goBack),
                ),
              ],
              ValueListenableBuilder(
                valueListenable: controller.textSizeNotifier,
                builder: (context, value, _) {
                  return SizedBox(
                    height: 100,
                    child: OverflowBar(
                      alignment: MainAxisAlignment.center,
                      overflowAlignment: OverflowBarAlignment.center,
                      children: [
                        Text(
                          context.l10n.textSizeLabel(value.floor()),
                          style: context.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Slider(
                          min: 10,
                          max: 26,
                          value: value.toDouble(),
                          // divisions: 1,
                          onChanged: (value) {
                            controller.textSizeNotifier.value = value.floor();
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),

              FilledButton.icon(
                onPressed: () {
                  if (controller.hasUnsavedChanges) {
                    controller.enableEditing = false;
                    controller.hasUnsavedChanges = false;
                  }
                },
                label: Text(context.l10n.saveButton),
                icon: Icon(Icons.save),
                style: filledBtnStyle,
              ),
            ],
          ),
          secondChild: OverflowBar(
            alignment: MainAxisAlignment.center,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: AppGaps.sm,
            overflowSpacing: AppGaps.xl,
            children: [
              if (Navigator.of(context).canPop())
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: filledBtnStyle,
                  child: Text(context.l10n.goBack),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  controller.enableEditing = true;
                  controller.hasUnsavedChanges = true;
                },
                label: Text(
                  context.l10n.editButton,
                  style: context.defaultTextStyle,
                ),
                icon: Icon(Icons.edit),
                style: filledBtnStyle,
              ),

              FilledButton.icon(
                onPressed: onExportAsImage,
                label: Text(context.l10n.exportAsImage),
                icon: Icon(Icons.image),
                style: filledBtnStyle,
              ),
              FilledButton.icon(
                onPressed: onExportAsPdf,
                label: Text(context.l10n.exportAsPdf),
                icon: Icon(Icons.file_open_rounded),
                style: filledBtnStyle,
              ),
            ],
          ),
          crossFadeState: editingEnabled
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: Duration(milliseconds: 300),
        );
      },
    );
  }
}
