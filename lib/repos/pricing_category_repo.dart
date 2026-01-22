// lib/repos/pricing_category_repo.dart

import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

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

  Future<PriceCategory?> getByUuid(String uuid) async {
    final result = await _db.query(
      DbConstants.tablePriceCategory,
      where: '${DbConstants.columnUuid} = ?',
      whereArgs: [uuid],
    );
    if (result.isEmpty) return null;
    return PriceCategory.fromMap(result.first);
  }

  Future<PriceCategory> insert(PriceCategory category) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final newUuid = const Uuid().v4();

    final id = await _db.insert(DbConstants.tablePriceCategory, {
      DbConstants.columnPriceCategoryName: category.name,
      DbConstants.columnPriceCategoryCurrency: category.currency,
      DbConstants.columnUuid: newUuid,
      DbConstants.columnUpdatedAt: now,
    });

    return category.copyWith(id: id, uuid: newUuid, updatedAt: now);
  }

  Future<void> delete(PriceCategory category) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    // Record tombstone for sync
    if (category.uuid.isNotEmpty) {
      await _db.insert(
        DbConstants.tableSyncTombstones,
        {
          'table_name': DbConstants.tablePriceCategory,
          'uuid': category.uuid,
          'deleted_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await _db.delete(
      DbConstants.tablePriceCategory,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [category.id],
    );
  }

  /// Delete by ID (legacy support)
  Future<void> deleteById(int id) async {
    // First get the category to record tombstone
    final result = await _db.query(
      DbConstants.tablePriceCategory,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [id],
    );

    if (result.isNotEmpty) {
      final category = PriceCategory.fromMap(result.first);
      if (category != null) {
        await delete(category);
        return;
      }
    }

    // Fallback if no UUID
    await _db.delete(
      DbConstants.tablePriceCategory,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [id],
    );
  }

  Future<PriceCategory> save({
    required String name,
    required String currency,
    PriceCategory? existing,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    if (existing?.id case final int id) {
      // Update existing
      await _db.update(
        DbConstants.tablePriceCategory,
        {
          DbConstants.columnPriceCategoryName: name,
          DbConstants.columnPriceCategoryCurrency: currency,
          DbConstants.columnUpdatedAt: now,
        },
        where: '${DbConstants.columnId} = ?',
        whereArgs: [id],
      );

      // Fetch updated record
      final result = await _db.query(
        DbConstants.tablePriceCategory,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [id],
      );

      return PriceCategory.fromMap(result.first)!;
    } else {
      // Insert new
      final newUuid = const Uuid().v4();

      final newId = await _db.insert(
        DbConstants.tablePriceCategory,
        {
          DbConstants.columnPriceCategoryName: name,
          DbConstants.columnPriceCategoryCurrency: currency,
          DbConstants.columnUuid: newUuid,
          DbConstants.columnUpdatedAt: now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return PriceCategory(
        id: newId,
        name: name,
        currency: currency,
        uuid: newUuid,
        updatedAt: now,
      );
    }
  }
}
