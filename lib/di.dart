import 'package:get_it/get_it.dart';

import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db/db_provider.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:i_gen/sync/sync_repo.dart';
import 'package:i_gen/sync/sync_service.dart';
import 'package:sqflite/sqflite.dart' show Database;

Future<void> injectDependencies() async {
  // open DB connection
  final db = await DbProvider.open();
  GetIt.I.registerSingleton<Database>(db);
  final productRepo = ProductRepo(db);
  GetIt.I.registerSingleton(productRepo);
  GetIt.I.registerSingleton(InvoiceRepo(db));
  GetIt.I.registerSingleton(CustomerRepo(db));
  GetIt.I.registerSingleton(ProductPricingRepo(db));
  GetIt.I.registerSingleton(PricingCategoryRepo(db));

  final storedProducts = await productRepo.getProducts();

  GetIt.I.registerSingleton(ProductsController(products: storedProducts));

  GetIt.I.registerSingleton<SyncRepository>(SyncRepository(db));
  GetIt.I.registerSingleton<SyncService>(
    SyncService(GetIt.I.get<SyncRepository>()),
  );
  await GetIt.I.allReady();
}
