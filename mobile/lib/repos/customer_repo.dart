import 'package:i_gen/db.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:sqflite/sqflite.dart';

/// Read-only repository over invoice customer names. It mutates no synced
/// table, so Phase 4 only requires hiding soft-deleted invoices here.
class CustomerRepo {
  final Database db;

  CustomerRepo(this.db);

  Future<List<String>> search(String query) async {
    final filter = await SyncMetadata.notDeletedClause(
      db,
      DbConstants.tableInvoice,
    );
    final res = await db.rawQuery(
      'Select Distinct ${DbConstants.columnCustomerName} from ${DbConstants.tableInvoice} where ${DbConstants.columnCustomerName} like ? AND $filter',
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
