import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/repos/backup_service.dart';
import 'package:i_gen/repos/customer_repo.dart';
import 'package:i_gen/repos/invoice_repo.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'package:i_gen/sync/sync_bootstrap.dart';

/// Absolute path of the live app database. The filename is single-sourced
/// from [DbProvider.dbFileName] — never copy the literal here.
Future<String> appDbPath() async {
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, DbProvider.dbFileName);
}

/// Builds a [BackupService] against the live app database, following the
/// frozen service contract (`db` + `dbPath` + `appDocDir`).
Future<BackupService> buildBackupService() async {
  final db = GetIt.I.get<Database>();
  final dbPath = await appDbPath();
  final docs = await getApplicationDocumentsDirectory();
  return BackupService(db: db, dbPath: dbPath, appDocDir: docs.path);
}

/// Startup hook: runs the periodic auto-backup without ever blocking launch
/// or throwing. Any failure (no disk space, locked db, first-run state)
/// degrades to a log line — login stays optional and launch stays offline.
Future<void> scheduleAutoBackup() async {
  try {
    final service = await buildBackupService();
    final prefs = await SharedPreferences.getInstance();
    await service.maybeAutoBackup(prefs);
  } catch (e) {
    debugPrint('Backup: auto-backup skipped: $e');
  }
}

/// Number of queued (unsynced) outbox rows on [db]. Used by the restore
/// confirmation dialog so the user knows how many local changes the backup
/// would replace.
Future<int> outboxPendingCount(Database db) async {
  final rows = await db.rawQuery(
    'SELECT COUNT(*) AS c FROM ${DbConstants.tableOutbox}',
  );
  if (rows.isEmpty) return 0;
  return (rows.first['c'] as num?)?.toInt() ?? 0;
}

/// Full restore orchestration for a caller-picked backup file.
///
/// The caller (settings UI) must validate the file first via
/// [BackupService.validateBackupFile] and confirm with the user when the
/// outbox is non-empty. Steps here: close the live db, swap files via the
/// service (it keeps one `<dbPath>.pre-restore` fallback), reopen via
/// [DbProvider.open], re-seat every GetIt registration that holds the old
/// [Database] handle (mirroring `injectDependencies`), re-wire the sync
/// engine, then trigger a post-restore sync.
///
/// A [StateError] from the post-restore sync propagates: the restore itself
/// succeeded, but the caller must surface the sync failure (silent skips
/// hide a diverged server).
Future<void> restoreDatabaseFromFile(String backupPath) async {
  final service = await buildBackupService();
  final oldDb = GetIt.I.get<Database>();
  final dbPath = await appDbPath();
  await oldDb.close();
  try {
    await service.restoreFromFile(backupPath);
  } catch (_) {
    // Swap failed: bring the previous database back online so the app is
    // never left without a usable handle, then surface the error.
    final reopened = await DbProvider.open(dbPath);
    await _reseatDatabase(reopened);
    rethrow;
  }
  final fresh = await DbProvider.open(dbPath);
  await _reseatDatabase(fresh);
  await SyncTrigger.instance.syncNow();
}

/// Replaces every GetIt registration that captures a [Database] handle.
/// Mirrors `injectDependencies` in `mobile/lib/di.dart` (Database + five repos +
/// products controller + sync engine wiring).
Future<void> _reseatDatabase(Database db) async {
  _replace<Database>(db);

  final productRepo = ProductRepo(db);
  _replace<ProductRepo>(productRepo);
  _replace<InvoiceRepo>(InvoiceRepo(db));
  _replace<CustomerRepo>(CustomerRepo(db));
  _replace<ProductPricingRepo>(ProductPricingRepo(db));
  _replace<PricingCategoryRepo>(PricingCategoryRepo(db));

  final stored = await productRepo.getProducts();
  _replace<ProductsController>(ProductsController(products: stored));

  // Re-binds the fresh handle; disposes the stale SyncService internally.
  await SyncBootstrap.wire(db);
}

void _replace<T extends Object>(T instance) {
  if (GetIt.I.isRegistered<T>()) {
    GetIt.I.unregister<T>();
  }
  GetIt.I.registerSingleton<T>(instance);
}
