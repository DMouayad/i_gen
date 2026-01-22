import 'package:flutter/foundation.dart';
import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class ProductPrice {
  final int productId;
  final String model;
  final double? price;
  final PriceCategory? priceCategory;
  final String uuid;
  final int updatedAt;

  ProductPrice({
    required this.productId,
    required this.model,
    required this.price,
    required this.priceCategory,
    this.uuid = '',
    this.updatedAt = 0,
  });

  ProductPrice copyWith({
    int? productId,
    String? model,
    double? price,
    PriceCategory? priceCategory,
    String? uuid,
    int? updatedAt,
  }) {
    return ProductPrice(
      productId: productId ?? this.productId,
      model: model ?? this.model,
      price: price ?? this.price,
      priceCategory: priceCategory ?? this.priceCategory,
      uuid: uuid ?? this.uuid,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

typedef ProductModel = String;
typedef PriceCategoryName = String;
typedef ProductsPricing =
    Map<ProductModel, Map<PriceCategoryName, ProductPrice>>;

class ProductPricingRepo {
  final Database _db;

  ProductPricingRepo(this._db);

  Future<ProductsPricing> getProductsPricing() async {
    final Map<ProductModel, Map<PriceCategoryName, ProductPrice>> prices = {};

    final queryResult = await _db.rawQuery('''
      SELECT 
        product.model AS p_model, 
        product._id AS p_id,
        product.uuid AS p_uuid,
        prices.price,
        prices.uuid AS price_uuid,
        prices.updated_at AS price_updated_at,
        price_category.name AS pc_name, 
        price_category.currency, 
        price_category._id AS pc_id,
        price_category.uuid AS pc_uuid,
        price_category.updated_at AS pc_updated_at
      FROM product 
      LEFT JOIN prices ON prices.product_id = product._id
      LEFT JOIN price_category ON prices.category_id = price_category._id
    ''');

    for (var res in queryResult) {
      if (res case {
        'p_model': String model,
        'p_id': int id,
        'price': double? price,
        'pc_id': int? priceCategoryId,
        'pc_name': String? priceCategoryName,
        'currency': String? currency,
      }) {
        if (!prices.containsKey(model)) {
          prices[model] = {};
        }

        final priceCategory = PriceCategory.fromMap({
          '_id': priceCategoryId,
          'name': priceCategoryName,
          'currency': currency,
          'uuid': res['pc_uuid'],
          'updated_at': res['pc_updated_at'],
        });

        if (priceCategory != null) {
          prices[model]?[priceCategory.name] = ProductPrice(
            productId: id,
            model: model,
            price: price,
            priceCategory: priceCategory,
            uuid: res['price_uuid'] as String? ?? '',
            updatedAt: res['price_updated_at'] as int? ?? 0,
          );
        }
      }
    }

    return prices;
  }
  // lib/repos/product_pricing_repo.dart

  Future<ProductPrice> save({
    required int priceCategoryId,
    required int productId,
    required num price,
    required String currency,
    String? existingUuid,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    _log(
      '💾 Saving price: productId=$productId, categoryId=$priceCategoryId, price=$price, timestamp=$now',
    );

    // Check if price entry already exists
    final existing = await _db.query(
      DbConstants.tablePrices,
      where:
          '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
      whereArgs: [productId, priceCategoryId],
    );

    String priceUuid;

    if (existing.isNotEmpty) {
      priceUuid =
          existing.first['uuid'] as String? ??
          existingUuid ??
          const Uuid().v4();
      final oldPrice = existing.first[DbConstants.columnPricesPrice];
      final oldUpdatedAt = existing.first[DbConstants.columnUpdatedAt];

      _log(
        '💾 Updating existing: old_price=$oldPrice, old_updated_at=$oldUpdatedAt, new_price=$price, new_updated_at=$now',
      );

      await _db.update(
        DbConstants.tablePrices,
        {
          DbConstants.columnPricesPrice: price,
          DbConstants.columnUuid: priceUuid,
          DbConstants.columnUpdatedAt: now,
        },
        where:
            '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
        whereArgs: [productId, priceCategoryId],
      );
    } else {
      priceUuid = existingUuid ?? const Uuid().v4();

      _log('💾 Inserting new: uuid=$priceUuid');

      await _db.insert(DbConstants.tablePrices, {
        DbConstants.columnPricesPriceCategoryId: priceCategoryId,
        DbConstants.columnPricesPrice: price,
        DbConstants.columnPricesProductId: productId,
        DbConstants.columnUuid: priceUuid,
        DbConstants.columnUpdatedAt: now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Verify save
    final saved = await _db.query(
      DbConstants.tablePrices,
      where:
          '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
      whereArgs: [productId, priceCategoryId],
    );
    _log('💾 Verified: ${saved.first}');

    // Get product model for return value
    final product = await _db.query(
      DbConstants.tableProduct,
      columns: [DbConstants.columnProductModel],
      where: '${DbConstants.columnId} = ?',
      whereArgs: [productId],
    );

    final model = product.isNotEmpty
        ? product.first[DbConstants.columnProductModel] as String
        : '';

    return ProductPrice(
      productId: productId,
      model: model,
      price: price.toDouble(),
      priceCategory: null, // Can fetch separately if needed
      uuid: priceUuid,
      updatedAt: now,
    );
    // ... rest of method
  }

  void _log(String message) {
    if (kDebugMode) {
      print('[PRICING] $message');
    }
  }
  // Future<ProductPrice> save({
  //   required int priceCategoryId,
  //   required int productId,
  //   required num price,
  //   required String currency,
  //   String? existingUuid,
  // }) async {
  //   final now = DateTime.now().toUtc().millisecondsSinceEpoch;

  //   // Check if price entry already exists
  //   final existing = await _db.query(
  //     DbConstants.tablePrices,
  //     where:
  //         '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
  //     whereArgs: [productId, priceCategoryId],
  //   );

  //   String priceUuid;

  //   if (existing.isNotEmpty) {
  //     // Update existing - keep the same UUID
  //     priceUuid =
  //         existing.first['uuid'] as String? ??
  //         existingUuid ??
  //         const Uuid().v4();

  //     await _db.update(
  //       DbConstants.tablePrices,
  //       {
  //         DbConstants.columnPricesPrice: price,
  //         DbConstants.columnUuid: priceUuid,
  //         DbConstants.columnUpdatedAt: now,
  //       },
  //       where:
  //           '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
  //       whereArgs: [productId, priceCategoryId],
  //     );
  //   } else {
  //     // Insert new
  //     priceUuid = existingUuid ?? const Uuid().v4();

  //     await _db.insert(DbConstants.tablePrices, {
  //       DbConstants.columnPricesPriceCategoryId: priceCategoryId,
  //       DbConstants.columnPricesPrice: price,
  //       DbConstants.columnPricesProductId: productId,
  //       DbConstants.columnUuid: priceUuid,
  //       DbConstants.columnUpdatedAt: now,
  //     }, conflictAlgorithm: ConflictAlgorithm.replace);
  //   }

  //   // Get product model for return value
  //   final product = await _db.query(
  //     DbConstants.tableProduct,
  //     columns: [DbConstants.columnProductModel],
  //     where: '${DbConstants.columnId} = ?',
  //     whereArgs: [productId],
  //   );

  //   final model = product.isNotEmpty
  //       ? product.first[DbConstants.columnProductModel] as String
  //       : '';

  //   return ProductPrice(
  //     productId: productId,
  //     model: model,
  //     price: price.toDouble(),
  //     priceCategory: null, // Can fetch separately if needed
  //     uuid: priceUuid,
  //     updatedAt: now,
  //   );
  // }

  Future<void> delete({
    required int productId,
    required int priceCategoryId,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    // Get UUID for tombstone
    final existing = await _db.query(
      DbConstants.tablePrices,
      columns: ['uuid'],
      where:
          '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
      whereArgs: [productId, priceCategoryId],
    );

    if (existing.isNotEmpty) {
      final uuid = existing.first['uuid'] as String?;
      if (uuid != null && uuid.isNotEmpty) {
        await _db.insert(
          DbConstants.tableSyncTombstones,
          {
            'table_name': DbConstants.tablePrices,
            'uuid': uuid,
            'deleted_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    await _db.delete(
      DbConstants.tablePrices,
      where:
          '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
      whereArgs: [productId, priceCategoryId],
    );
  }
}
