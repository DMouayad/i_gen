import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/models/product.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class ProductRepo {
  final Database db;

  ProductRepo(this.db);

  Future<Product> insertProduct({
    required String model,
    required String name,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final uuid = const Uuid().v4();

    final id = await db.insert(DbConstants.tableProduct, {
      DbConstants.columnProductModel: model,
      DbConstants.columnProductName: name,
      DbConstants.columnUuid: uuid,
      DbConstants.columnUpdatedAt: now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    return Product(
      id: id,
      model: model,
      name: name,
      uuid: uuid,
      updatedAt: now,
    );
  }

  Future<List<Product>> getProducts() async {
    // ✅ Simple query - returns all columns with original names
    final maps = await db.query(DbConstants.tableProduct);
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<bool> editProduct(Product product) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    final updatedCount = await db.update(
      DbConstants.tableProduct,
      {
        DbConstants.columnProductModel: product.model,
        DbConstants.columnProductName: product.name,
        DbConstants.columnUpdatedAt: now,
      },
      where: '${DbConstants.columnId} = ?',
      whereArgs: [product.id],
    );
    return updatedCount > 0;
  }

  Future<bool> deleteProduct(Product product) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    // Record tombstone for sync
    if (product.uuid.isNotEmpty) {
      await db.insert(
        DbConstants.tableSyncTombstones,
        {
          'table_name': DbConstants.tableProduct,
          'uuid': product.uuid,
          'deleted_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final deletedCount = await db.delete(
      DbConstants.tableProduct,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [product.id],
    );
    return deletedCount > 0;
  }

  Future<Product?> getByUuid(String uuid) async {
    final result = await db.query(
      DbConstants.tableProduct,
      where: '${DbConstants.columnUuid} = ?',
      whereArgs: [uuid],
    );
    if (result.isEmpty) return null;
    return Product.fromMap(result.first);
  }
}
