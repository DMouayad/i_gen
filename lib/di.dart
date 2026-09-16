import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:get_it/get_it.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/db_seeder.dart';
import 'package:i_gen/orders/order_watcher.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:i_gen/repos/sync_maintenance.dart';
import 'package:i_gen/sync/sync_bootstrap.dart';

Future<void> injectDependencies() async {
  // open DB connection
  final dbDir = await getApplicationSupportDirectory();
  final dbPath = p.join(dbDir.path, 'i_gen.db');

  final db = await DbProvider.open(dbPath);
  if (!GetIt.I.isRegistered<Database>()) {
    GetIt.I.registerSingleton<Database>(db);
  }

  // Seed + backfill never block startup: degrade to a log line on failure.
  try {
    await DbSeeder.seedProducts(db);
  } catch (e) {
    debugPrint('DbSeeder: seed skipped: $e');
  }

  // Backfill: existing installs already have the 25 catalog rows but an
  // empty outbox. Idempotent, single-query.
  try {
    await SyncMaintenance.backfillSeedOutbox(db);
  } catch (e) {
    debugPrint('SyncMaintenance: backfillSeedOutbox failed: $e');
  }

  // Phase 5 startup maintenance pass (tombstone purge, parked-op cap).
  // Never blocks startup: degrades to a log line on any failure.
  try {
    final summary = await SyncMaintenance.runStartupMaintenance(db);
    debugPrint(
      'SyncMaintenance: startup pass purged ${summary.tombstonesPurged} '
      'tombstone(s), evicted ${summary.parkedEvicted} parked op(s).',
    );
  } catch (e) {
    debugPrint('SyncMaintenance: startup pass failed: $e');
  }
  final productRepo = ProductRepo(db);
  GetIt.I.registerSingleton(productRepo);
  GetIt.I.registerSingleton(InvoiceRepo(db));
  GetIt.I.registerSingleton(CustomerRepo(db));
  GetIt.I.registerSingleton(ProductPricingRepo(db));
  GetIt.I.registerSingleton(PricingCategoryRepo(db));

  final storedProducts = await productRepo.getProducts();

  GetIt.I.registerSingleton(ProductsController(products: storedProducts));

  // Sync engine wiring (gateway + service + triggers). Never throws, never
  // blocks: unwired means changes queue safely in the outbox.
  await SyncBootstrap.wire(db);

  // Order watcher wiring (staff new-order alerts). Same contract: never
  // throws, never blocks — unwired means no alerts, reads unaffected.
  await OrderWatcher.wire();

  await GetIt.I.allReady();
}
