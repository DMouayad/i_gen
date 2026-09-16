import 'package:flutter/material.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/utils/context_extensions.dart';

class PreventPop extends StatelessWidget {
  const PreventPop({super.key, required this.child, required this.controller});

  final Widget child;
  final InvoiceDetailsController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller.hasUnsavedChangesNotifier,
      builder: (context, _) {
        return PopScope(
          canPop: !controller.hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _handlePopBlocked(context);
          },
          child: child,
        );
      },
    );
  }

  Future<void> _handlePopBlocked(BuildContext context) async {
    // Check if context is still valid
    if (!context.mounted) return;

    // Show confirmation dialog for unsaved changes
    final shouldDiscard = await _showDiscardDialog(context);

    if (shouldDiscard == true && context.mounted) {
      controller.hasUnsavedChanges = false;
      Navigator.of(context).pop();
    }
  }

  Future<bool?> _showDiscardDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        icon: Icon(
          Icons.warning_amber_rounded,
          color: context.colorScheme.error,
          size: 48,
        ),
        title: Text(context.l10n.discardChangesTitle),
        content: Text(
          context.l10n.discardChangesMessage,
          style: context.textTheme.bodyLarge,
        ),
        actions: [
          OutlinedButton(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(64, 48)),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.keepEditing),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
              minimumSize: const Size(64, 48),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.discardButton),
          ),
        ],
      ),
    );
  }
}
