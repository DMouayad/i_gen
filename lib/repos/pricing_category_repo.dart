import 'package:i_gen/db.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:sqflite/sqflite.dart';

class PricingCategoryRepo {
  final Database _db;

  PricingCategoryRepo(this._db);

  Future<List<PriceCategory>> getAll() async {
    final List<PriceCategory> result = [];
    final List<Map<String, dynamic>> categories = await _db.query(
      DbConstants.tablePriceCategory,
    );

    for (final item in categories) {
      if (PriceCategory.fromMap(item) case PriceCategory category) {
        result.add(category);
      }
    }
    return result;
  }

  Future<int> insert(PriceCategory category) async {
    return await _db.insert(DbConstants.tablePriceCategory, {
      DbConstants.columnPriceCategoryName: category.name,
      DbConstants.columnPriceCategoryCurrency: category.currency,
    });
  }

  Future<void> delete(int id) async {
    await _db.delete(
      DbConstants.tablePriceCategory,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [id],
    );
  }

  Future<int> save({
    required String name,
    required String currency,
    int? id,
  }) async {
    return await _db.insert(DbConstants.tablePriceCategory, {
      DbConstants.columnPriceCategoryName: name,
      DbConstants.columnPriceCategoryCurrency: currency,
      DbConstants.columnPriceCategoryId: id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
