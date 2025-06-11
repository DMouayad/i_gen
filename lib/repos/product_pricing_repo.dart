import 'package:i_gen/db.dart';
import 'package:i_gen/models/price_category.dart';
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
    final queryResult = await _db.rawQuery('''
select product.model as "p_model", product._id as "p_id", prices.price, price_category.name as "pc_name", price_category.currency, price_category._id as "pc_id" from 
product left join prices on prices.product_id = product._id
left join price_category on prices.category_id = price_category._id''');
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
    await _db.insert(DbConstants.tablePrices, {
      DbConstants.columnPricesPriceCategoryId: priceCategoryId,
      DbConstants.columnPricesPrice: price,
      DbConstants.columnPricesProductId: productId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
