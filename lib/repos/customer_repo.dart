import 'package:i_gen/db.dart';
import 'package:sqflite/sqflite.dart';

class CustomerRepo {
  final Database db;

  CustomerRepo(this.db);

  Future<List<String>> search(String query) async {
    final res = await db.query(
      DbConstants.tableInvoice,
      columns: [DbConstants.columnCustomerName],
      where: '${DbConstants.columnCustomerName} like ?',
      whereArgs: ['%$query%'],
    );
    final names = <String>[];
    for (var e in res) {
      if (e[DbConstants.columnCustomerName] case String name) {
        names.add(name);
      }
    }
    return names;
  }
}
