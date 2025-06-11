import 'package:i_gen/db.dart';
import 'package:i_gen/models/product.dart';
import 'package:sqflite/sqflite.dart';

class ProductRepo {
  final Database db;

  ProductRepo(this.db);

  Future<Product> insertProduct({String? model, String? name}) async {
    final id = await db.insert(DbConstants.tableProduct, {
      DbConstants.columnProductModel: model,
      DbConstants.columnProductName: name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return Product(id: id, model: model!, name: name!);
  }

  Future<List<Product>> getProducts() async {
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT ${DbConstants.columnId} as id, ${DbConstants.columnProductModel} as model, ${DbConstants.columnProductName} as name
      FROM ${DbConstants.tableProduct}
      ''');
    return List.generate(maps.length, (i) => Product.fromMap(maps[i])!);
  }

  Future<bool> editProduct(Product product) async {
    final updatedCount = await db.update(
      DbConstants.tableProduct,
      product.toMap(),
      where: '${DbConstants.columnId} = ?',
      whereArgs: [product.id],
    );
    return updatedCount > 0;
  }

  Future<bool> deleteProduct(Product product) async {
    final deletedCount = await db.delete(
      DbConstants.tableProduct,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [product.id],
    );
    return deletedCount > 0;
  }
}
