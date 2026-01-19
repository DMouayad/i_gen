import 'package:flutter/material.dart';
import 'package:i_gen/controllers/invoice_details_controller.dart';
import 'package:i_gen/utils/context_extensions.dart';

class PreventPop extends StatelessWidget {
  const PreventPop({
    super.key,
    required this.child,
    required this.controller,
    this.prevent = false,
  });

  final Widget child;
  final InvoiceDetailsController controller;
  final bool prevent;

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

    // If prevent is true (hard block), don't show dialog - just block
    if (prevent) return;

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
        icon: Icon(
          Icons.warning_amber_rounded,
          color: context.colorScheme.error,
          size: 48,
        ),
        title: const Text('Discard Changes?'),
        content: Text(
          'You have unsaved changes. Are you sure you want to discard them?',
          style: context.textTheme.bodyLarge,
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }
}
