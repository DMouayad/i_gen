import 'package:flutter/material.dart';

import 'package:i_gen/models/product.dart';
import 'package:i_gen/utils/context_extensions.dart';

/// Multi-select size picker shared by the desktop grid cell and the mobile
/// product dialog: chips for every [kSizeOrder] label plus a free-text field
/// for custom labels. Confirm returns the sorted selection, cancel null.
Future<List<String>?> showSizeMultiSelect(
  BuildContext context, {
  required List<String> initial,
  String? title,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (context) =>
        _SizeMultiSelectDialog(initial: initial, title: title),
  );
}

class _SizeMultiSelectDialog extends StatefulWidget {
  const _SizeMultiSelectDialog({required this.initial, this.title});

  final List<String> initial;
  final String? title;

  @override
  State<_SizeMultiSelectDialog> createState() => _SizeMultiSelectDialogState();
}

class _SizeMultiSelectDialogState extends State<_SizeMultiSelectDialog> {
  late final Set<String> _selected = {...widget.initial};
  late final TextEditingController _custom = TextEditingController(
    text: widget.initial.where((s) => !kSizeOrder.contains(s)).join(', '),
  );

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _confirm() {
    final custom = Product.parseSizeList(_custom.text).toSet();
    // Custom text can only add: unchecking a chip while its label sits in
    // the custom field must not silently drop it.
    custom.addAll(_selected.where(kSizeOrder.contains));
    Navigator.of(context).pop(Product.sortSizes(custom.toList()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.dialog),
      ),
      title: Text(widget.title ?? context.l10n.sizesColumn),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppGaps.sm,
              runSpacing: AppGaps.sm,
              children: [
                for (final size in kSizeOrder)
                  FilterChip(
                    label: Text(size),
                    selected: _selected.contains(size),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selected.add(size);
                      } else {
                        _selected.remove(size);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppGaps.md),
            TextField(
              controller: _custom,
              decoration: InputDecoration(
                labelText: context.l10n.customSizesHint,
                hintText: '4XL, Tall',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(64, 48)),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancelButton),
        ),
        FilledButton(
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(64, 48)),
          ),
          onPressed: _confirm,
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}
