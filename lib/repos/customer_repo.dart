import 'package:i_gen/db.dart';
import 'package:sqflite/sqflite.dart';

class CustomerRepo {
  final Database db;

  CustomerRepo(this.db);

  Future<List<String>> search(String query) async {
    final res = await db.rawQuery(
      'Select Distinct ${DbConstants.columnCustomerName} from ${DbConstants.tableInvoice} where ${DbConstants.columnCustomerName} like ?',

      ['%$query%'],
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
