import 'package:i_gen/db.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:sqflite/sqflite.dart';

/// Seeds the bundled product catalog on fresh installs.
///
/// Lives outside `db.dart` so the schema file stays dependency-free
/// (`db.dart` <- `sync_metadata.dart` <- this file; no cycle).
/// Each seeded row is enqueued as an `insert` op so the first sync
/// after sign-in pushes the catalog.
class DbSeeder {
  DbSeeder._();

  /// 25 rows (note the gap: `_id` 7 was never assigned).
  static Future<void> seedProducts(Database db) async {
    // DDL outside the transaction: cheaper and avoids DDL-in-txn.
    await SyncMetadata.ensureOutboxTable(db);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final count =
          (await txn.rawQuery(
                'select count(*) as c from ${DbConstants.tableProduct}',
              )).first['c']
              as int? ??
          0;
      if (count != 0) return;
      for (final product in _products) {
        await txn.insert(DbConstants.tableProduct, {
          DbConstants.columnId: product.$1,
          DbConstants.columnProductModel: product.$2,
          DbConstants.columnProductName: product.$3,
          DbConstants.columnUpdatedAt: now,
          DbConstants.columnIsDeleted: 0,
        });
        // Deterministic key per model: a second device pushing the same
        // bundled catalog upserts onto the same server rows (same owner)
        // instead of creating duplicate twins that break pull merges.
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tableProduct,
            rowId: product.$1,
            op: DbConstants.opInsert,
          ),
          opIdOverride: DbConstants.seedOpId(
            DbConstants.tableProduct,
            product.$2,
          ),
        );
      }
    });
  }

  static const List<(int, String, String)> _products = [
    (1, 'A1', 'مشد صدر'),
    (2, 'A1+', 'مشد صدر عريض'),
    (3, 'B1', 'مشد حزام بطن'),
    (4, 'D1', 'سليب بطن'),
    (5, 'D2', 'سليب بطن ظهر عالي'),
    (6, 'C1', 'شورت فوق الركبة'),
    (8, 'C2', 'شورت تحت الركبة'),
    (9, 'A2', 'مشد بودي صدر مع بطن'),
    (10, 'A3', 'مشد بودي مع أكمام'),
    (11, 'H1', 'مشد ذراعين'),
    (12, 'H2', 'مشد ذراعين عريض'),
    (13, 'K1', 'شورت فوق الركبة مع خلفية تول'),
    (14, 'K2', 'شورت تحت الركبة مع خلفية تول'),
    (15, 'K3', 'أفارول فوق الركبة مع خلفية تول'),
    (16, 'K4', 'أفارول للكاحل مع خلفية تول'),
    (17, 'K5', 'أفارول كامل مع يدين مع خلفية تول'),
    (18, 'E1', 'مشد تثدي رجالي'),
    (19, 'E2', 'كنزة حفر رجالي'),
    (20, 'E3', 'أفارول رجالي فوق الركبة'),
    (21, 'G1', 'أفارول نسائي فوق الركبة'),
    (22, 'G2', 'أفارول نسائي للكاحل'),
    (23, 'M1', 'مشد فخذين'),
    (24, 'C3', 'مشد طويل للكاحل'),
    (25, 'S1', 'مشد عنق'),
    (26, 'S2', 'مشد وجه'),
  ];
}
