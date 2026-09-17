import 'package:get_it/get_it.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/product_repo.dart';

class ProductsController {
  final Map<String, Product> _products;

  ProductsController({required List<Product> products})
    : _products = Map.fromEntries(products.map((e) => MapEntry(e.model, e)));

  Map<String, Product> get products => _products;

  /// Re-reads the catalog from the database (e.g. after a sync pulled
  /// rows). The map object stays identical so existing readers keep working;
  /// callers rebuild their rows/lists afterwards via setState.
  Future<void> reload() async {
    final fresh = await GetIt.I.get<ProductRepo>().getProducts();
    _products
      ..clear()
      ..addEntries(fresh.map((e) => MapEntry(e.model, e)));
  }

  Future<void> save({
    required String model,
    required String name,
    List<String> sizes = const [],
  }) async {
    final newProduct = await GetIt.I.get<ProductRepo>().insertProduct(
      model: model,
      name: name,
      sizes: sizes,
    );

    _products[newProduct.model] = newProduct;
  }

  Future<void> deleteProduct(Product product) async {
    final deleted = await GetIt.I.get<ProductRepo>().deleteProduct(product);
    if (deleted) {
      _products.remove(product.model);
    }
  }
}
