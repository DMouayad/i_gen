import 'package:flutter/material.dart';
import 'package:i_gen/utils/context_extensions.dart';
import 'package:trina_grid/trina_grid.dart';

Widget trinaDropDownRenderer(
  BuildContext context,
  Widget defaultEditCellWidget,
  TrinaCell cell,
  TextEditingController controller,
  FocusNode focusNode,
  dynamic Function(dynamic)? handleSelected,
  void Function(dynamic newValue) onChanged,
) {
  final textStyle = context.textTheme.bodyLarge!.copyWith(
    fontWeight: FontWeight.w600,
  );
  String? value = cell.value;
  Color indicatorColor = context.colorScheme.secondary;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: AppGaps.sm),
    decoration: BoxDecoration(
      color: context.colorScheme.surface,
      border: Border.all(color: context.colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(AppRadii.control),
    ),
    child: StatefulBuilder(
      builder: (context, mSetState) {
        return DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            style: textStyle.copyWith(color: context.colorScheme.onSurface),
            isExpanded: true,
            icon: Icon(Icons.arrow_drop_down, color: indicatorColor),
            onChanged: (String? newValue) {
              handleSelected?.call(newValue);
              mSetState(() {
                value = newValue;
              });
              onChanged(newValue);
            },
            items: (cell.column.type as TrinaColumnTypeSelect).items
                .map<DropdownMenuItem<String>>((dynamic value) {
                  return DropdownMenuItem<String>(
                    value: value as String,
                    child: Text(value),
                  );
                })
                .toList(),
          ),
        );
      },
    ),
  );
}
