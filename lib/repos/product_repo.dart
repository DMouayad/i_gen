import 'package:i_gen/db.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:sqflite/sqflite.dart';

class ProductRepo {
  final Database db;

  ProductRepo(this.db);

  /// Inserts a product, or updates the existing row when [model] already
  /// exists. Update-in-place keeps a stable `_id` — `REPLACE` is banned on
  /// synced tables (it deletes + reinserts, orphaning `remote_id` matches).
  Future<Product> insertProduct({String? model, String? name}) async {
    return await db.transaction((txn) async {
      final existing = await txn.query(
        DbConstants.tableProduct,
        columns: [DbConstants.columnId],
        where: '${DbConstants.columnProductModel} = ?',
        whereArgs: [model],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.first[DbConstants.columnId] as int;
        final values =
            await SyncMetadata.withStamp(txn, DbConstants.tableProduct, {
              DbConstants.columnProductModel: model,
              DbConstants.columnProductName: name,
            });
        await txn.update(
          DbConstants.tableProduct,
          values,
          where: '${DbConstants.columnId} = ?',
          whereArgs: [id],
        );
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tableProduct,
            rowId: id,
            op: DbConstants.opUpdate,
          ),
        );
        return Product(id: id, model: model!, name: name!);
      }
      final values = await SyncMetadata.withStamp(
        txn,
        DbConstants.tableProduct,
        {
          DbConstants.columnProductModel: model,
          DbConstants.columnProductName: name,
        },
      );
      final id = await txn.insert(DbConstants.tableProduct, values);
      await SyncMetadata.recordMutation(
        txn,
        ref: MutationRef(
          table: DbConstants.tableProduct,
          rowId: id,
          op: DbConstants.opInsert,
        ),
      );
      return Product(id: id, model: model!, name: name!);
    });
  }

  Future<List<Product>> getProducts() async {
    final filter = await SyncMetadata.notDeletedClause(
      db,
      DbConstants.tableProduct,
    );
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT ${DbConstants.columnId} as id, ${DbConstants.columnProductModel} as model, ${DbConstants.columnProductName} as name
      FROM ${DbConstants.tableProduct}
      WHERE $filter
      ''');
    return List.generate(maps.length, (i) => Product.fromMap(maps[i])!);
  }

  Future<bool> editProduct(Product product) async {
    return await db.transaction((txn) async {
      // NOTE: Product.toMap() keys ('id', ...) do not match the table
      // columns ('_id', ...); passing it straight to update crashes with
      // "no such column: id" (pre-existing bug). Map fields explicitly.
      final values =
          await SyncMetadata.withStamp(txn, DbConstants.tableProduct, {
            DbConstants.columnProductModel: product.model,
            DbConstants.columnProductName: product.name,
          });
      final updatedCount = await txn.update(
        DbConstants.tableProduct,
        values,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [product.id],
      );
      if (updatedCount > 0) {
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tableProduct,
            rowId: product.id,
            op: DbConstants.opUpdate,
          ),
        );
      }
      return updatedCount > 0;
    });
  }

  Future<bool> deleteProduct(Product product) async {
    return await db.transaction((txn) async {
      final before = await SyncMetadata.softDelete(
        txn,
        DbConstants.tableProduct,
        product.id,
      );
      await SyncMetadata.recordMutation(
        txn,
        ref: MutationRef(
          table: DbConstants.tableProduct,
          rowId: product.id,
          op: DbConstants.opDelete,
        ),
        payloadOverride: before,
      );
      return true;
    });
  }
}
