import 'package:i_gen/db.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:sqflite/sqflite.dart';

class PricingCategoryRepo {
  final Database _db;

  PricingCategoryRepo(this._db);

  Future<List<PriceCategory>> getAll() async {
    final filter = await SyncMetadata.notDeletedClause(
      _db,
      DbConstants.tablePriceCategory,
    );
    final List<PriceCategory> result = [];
    final List<Map<String, dynamic>> categories = await _db.query(
      DbConstants.tablePriceCategory,
      where: filter == '1 = 1' ? null : filter,
    );

    for (final item in categories) {
      if (PriceCategory.fromMap(item) case PriceCategory category) {
        result.add(category);
      }
    }
    return result;
  }

  Future<int> insert(PriceCategory category) async {
    return await _db.transaction((txn) async {
      final values =
          await SyncMetadata.withStamp(txn, DbConstants.tablePriceCategory, {
            DbConstants.columnPriceCategoryName: category.name,
            DbConstants.columnPriceCategoryCurrency: category.currency,
          });
      final id = await txn.insert(DbConstants.tablePriceCategory, values);
      await SyncMetadata.recordMutation(
        txn,
        ref: MutationRef(
          table: DbConstants.tablePriceCategory,
          rowId: id,
          op: DbConstants.opInsert,
        ),
      );
      return id;
    });
  }

  Future<void> delete(int id) async {
    await _db.transaction((txn) async {
      final before = await SyncMetadata.softDelete(
        txn,
        DbConstants.tablePriceCategory,
        id,
      );
      await SyncMetadata.recordMutation(
        txn,
        ref: MutationRef(
          table: DbConstants.tablePriceCategory,
          rowId: id,
          op: DbConstants.opDelete,
        ),
        payloadOverride: before,
      );
    });
  }

  Future<int> save({
    required String name,
    required String currency,
    int? id,
  }) async {
    return await _db.transaction((txn) async {
      final existing = await _findExisting(txn, id: id, name: name);
      if (existing != null) {
        final existingId = existing[DbConstants.columnId] as int;
        final values =
            await SyncMetadata.withStamp(txn, DbConstants.tablePriceCategory, {
              DbConstants.columnPriceCategoryName: name,
              DbConstants.columnPriceCategoryCurrency: currency,
            });
        await txn.update(
          DbConstants.tablePriceCategory,
          values,
          where: '${DbConstants.columnId} = ?',
          whereArgs: [existingId],
        );
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tablePriceCategory,
            rowId: existingId,
            op: DbConstants.opUpdate,
          ),
        );
        return existingId;
      }
      final values =
          await SyncMetadata.withStamp(txn, DbConstants.tablePriceCategory, {
            if (id case final existingId)
              DbConstants.columnPriceCategoryId: existingId,
            DbConstants.columnPriceCategoryName: name,
            DbConstants.columnPriceCategoryCurrency: currency,
          });
      final newId = await txn.insert(DbConstants.tablePriceCategory, values);
      await SyncMetadata.recordMutation(
        txn,
        ref: MutationRef(
          table: DbConstants.tablePriceCategory,
          rowId: newId,
          op: DbConstants.opInsert,
        ),
      );
      return newId;
    });
  }

  /// Explicit update/insert check replacing the old
  /// `INSERT ... ON CONFLICT REPLACE` so the row keeps a stable `_id`
  /// (replace would delete + reinsert, breaking `remote_id` matching).
  Future<Map<String, Object?>?> _findExisting(
    Transaction txn, {
    required int? id,
    required String name,
  }) async {
    if (id != null) {
      final byId = await txn.query(
        DbConstants.tablePriceCategory,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (byId.isNotEmpty) return byId.first;
    }
    final byName = await txn.query(
      DbConstants.tablePriceCategory,
      where: '${DbConstants.columnPriceCategoryName} = ?',
      whereArgs: [name],
      limit: 1,
    );
    return byName.isEmpty ? null : byName.first;
  }
}
