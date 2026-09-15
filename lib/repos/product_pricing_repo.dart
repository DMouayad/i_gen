import 'package:i_gen/db.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:sqflite/sqflite.dart';

class ProductPrice {
  final int productId;
  final String model;
  final double? price;
  final PriceCategory? priceCategory;

  ProductPrice({
    required this.productId,
    required this.model,
    required this.price,
    required this.priceCategory,
  });
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
    final productFilter = await SyncMetadata.notDeletedClause(
      _db,
      DbConstants.tableProduct,
      alias: DbConstants.tableProduct,
    );
    final pricesFilter = await SyncMetadata.notDeletedClause(
      _db,
      DbConstants.tablePrices,
      alias: DbConstants.tablePrices,
    );
    final categoryFilter = await SyncMetadata.notDeletedClause(
      _db,
      DbConstants.tablePriceCategory,
      alias: DbConstants.tablePriceCategory,
    );
    final queryResult = await _db.rawQuery('''
select product.model as "p_model", product._id as "p_id", prices.price, price_category.name as "pc_name", price_category.currency, price_category._id as "pc_id" from 
product left join prices on prices.product_id = product._id
left join price_category on prices.category_id = price_category._id
where $productFilter
  and (prices.${DbConstants.columnId} is null or $pricesFilter)
  and (price_category.${DbConstants.columnId} is null or $categoryFilter)''');
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
        });
        if (priceCategory != null) {
          prices[model]?[priceCategory.name] = ProductPrice(
            productId: id,
            model: model,
            price: price,
            priceCategory: priceCategory,
          );
        }
      }
    }
    return prices;
  }

  Future<void> save({
    required int priceCategoryId,
    required int productId,
    required num price,
    required String currency,
  }) async {
    await _db.transaction((txn) async {
      final existing = await txn.query(
        DbConstants.tablePrices,
        columns: [DbConstants.columnId],
        where:
            '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
        whereArgs: [productId, priceCategoryId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final rowId = existing.first[DbConstants.columnId] as int;
        final values =
            await SyncMetadata.withStamp(txn, DbConstants.tablePrices, {
              DbConstants.columnPricesPriceCategoryId: priceCategoryId,
              DbConstants.columnPricesPrice: price,
              DbConstants.columnPricesProductId: productId,
            });
        await txn.update(
          DbConstants.tablePrices,
          values,
          where: '${DbConstants.columnId} = ?',
          whereArgs: [rowId],
        );
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tablePrices,
            rowId: rowId,
            op: DbConstants.opUpdate,
          ),
        );
        return;
      }
      final values =
          await SyncMetadata.withStamp(txn, DbConstants.tablePrices, {
            DbConstants.columnPricesPriceCategoryId: priceCategoryId,
            DbConstants.columnPricesPrice: price,
            DbConstants.columnPricesProductId: productId,
          });
      final rowId = await txn.insert(DbConstants.tablePrices, values);
      await SyncMetadata.recordMutation(
        txn,
        ref: MutationRef(
          table: DbConstants.tablePrices,
          rowId: rowId,
          op: DbConstants.opInsert,
        ),
      );
    });
  }
}
