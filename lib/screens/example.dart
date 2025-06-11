import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';

class Example extends StatefulWidget {
  const Example({super.key});

  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  final columns = [
    TrinaColumn(
      field: 'id',
      title: 'ID',
      type: TrinaColumnType.number(),
      renderer: (context) => Text(context.cell.value.toString()),
    ),
    TrinaColumn(
      field: 'name',
      title: 'Name',
      type: TrinaColumnType.text(),
      renderer: (context) => Text(context.cell.value.toString()),
    ),
    TrinaColumn(
      field: 'age',
      title: 'Age',
      type: TrinaColumnType.number(),
      renderer: (context) => Text(context.cell.value.toString()),
    ),
  ];

  final rows = [
    TrinaRow(
      cells: {
        'id': TrinaCell(value: 1),
        'name': TrinaCell(value: 'John'),
        'age': TrinaCell(value: 30),
      },
    ),
    TrinaRow(
      cells: {
        'id': TrinaCell(value: 2),
        'name': TrinaCell(value: 'Mary'),
        'age': TrinaCell(value: 25),
      },
    ),
    TrinaRow(
      cells: {
        'id': TrinaCell(value: 3),
        'name': TrinaCell(value: 'Mike'),
        'age': TrinaCell(value: 35),
      },
    ),
  ];
  @override
  Widget build(BuildContext context) {
    return TrinaGrid(
      columns: columns,
      rows: rows,
      configuration: TrinaGridConfiguration(
        style: TrinaGridStyleConfig(
          enableCellBorderHorizontal: false,
          borderColor: Colors.black26,
          rowHeight: 60,
        ),
      ),
    );
  }
}
