import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:i_gen/db.dart';
import 'package:i_gen/repos/backup_service.dart';
import 'test_helper.dart';

Future<Directory> _tempDir(String prefix) =>
    Directory.systemTemp.createTemp(prefix);

List<File> _autoBackups(Directory dir) =>
    dir.listSync().whereType<File>().where((f) {
      final name = p.basename(f.path);
      return name.startsWith('auto-backup-') && name.endsWith('.db');
    }).toList();

Future<int> _insertSampleRows(Database db) async {
  final productId = await db.insert(DbConstants.tableProduct, {
    DbConstants.columnProductModel: 'BK-1',
    DbConstants.columnProductName: 'backup-widget',
    DbConstants.columnProductSizes: '[]',
    DbConstants.columnUpdatedAt: 1,
    DbConstants.columnIsDeleted: 0,
  });
  final invoiceId = await db.insert(DbConstants.tableInvoice, {
    DbConstants.columnInvoiceTotal: 42.0,
    DbConstants.columnCustomerName: 'acme',
    DbConstants.columnInvoiceDate: '2026-09-17',
    DbConstants.columnInvoiceCurrency: 'USD',
    DbConstants.columnInvoiceDiscount: 0.0,
    DbConstants.columnUpdatedAt: 1,
    DbConstants.columnIsDeleted: 0,
  });
  await db.insert(DbConstants.tableInvoiceLine, {
    DbConstants.columnInvoiceLineInvoiceId: invoiceId,
    DbConstants.columnInvoiceLineProductId: productId,
    DbConstants.columnInvoiceLineAmount: 2,
    DbConstants.columnInvoiceLinePrice: 21.0,
    DbConstants.columnInvoiceLineSize: '',
    DbConstants.columnUpdatedAt: 1,
    DbConstants.columnIsDeleted: 0,
  });
  await db.insert(DbConstants.tableOutbox, {
    DbConstants.columnOpId: 'op-backup-1',
    DbConstants.columnTableName: DbConstants.tableProduct,
    DbConstants.columnRowId: productId,
    DbConstants.columnOp: DbConstants.opInsert,
    DbConstants.columnPayload: '{}',
    DbConstants.columnCreatedAt: 1,
    DbConstants.columnAttempts: 0,
  });
  return productId;
}

void main() {
  test('backup round-trip preserves rows and outbox across restore', () async {
    final db = await openFreshTestDb();
    final dbPath = db.path;
    await _insertSampleRows(db);

    final dir = await _tempDir('i_gen_backup_test');
    final backupPath = p.join(dir.path, 'manual.db');
    final service = BackupService(db: db, dbPath: dbPath, appDocDir: dir.path);
    await service.backupToFile(backupPath);
    expect(await File(backupPath).exists(), isTrue);

    // Simulate data loss on the live db, then close (restore contract:
    // the caller closes before swapping files).
    await db.delete(DbConstants.tableInvoiceLine);
    await db.delete(DbConstants.tableInvoice);
    await db.delete(DbConstants.tableProduct);
    await db.delete(DbConstants.tableOutbox);
    expect(await tableCount(db, DbConstants.tableProduct), 0);
    await db.close();

    await service.restoreFromFile(backupPath);
    expect(await File('$dbPath.pre-restore').exists(), isTrue);

    final reopened = await reopenViaProvider(dbPath);
    expect(await tableCount(reopened, DbConstants.tableProduct), 1);
    expect(await tableCount(reopened, DbConstants.tableInvoice), 1);
    expect(await tableCount(reopened, DbConstants.tableInvoiceLine), 1);
    expect(await tableCount(reopened, DbConstants.tableOutbox), 1);
    final products = await reopened.query(DbConstants.tableProduct);
    expect(products.first[DbConstants.columnProductModel], 'BK-1');
    final outbox = await outboxRows(reopened);
    expect(outbox.single[DbConstants.columnOpId], 'op-backup-1');
    await reopened.close();
  });

  test('v1 fixture backup restores and migrates on reopen', () async {
    final v1 = await openV1Fixture();
    final dbPath = v1.path;
    final before = <String, int>{};
    for (final table in DbConstants.syncedTables) {
      before[table] = await tableCount(v1, table);
    }
    expect(before.values.every((c) => c > 0), isTrue);

    final dir = await _tempDir('i_gen_backup_v1_test');
    final backupPath = p.join(dir.path, 'v1.db');
    final service = BackupService(db: v1, dbPath: dbPath, appDocDir: dir.path);
    await service.backupToFile(backupPath);
    await BackupService.validateBackupFile(backupPath);
    await v1.close();

    await service.restoreFromFile(backupPath);
    final db = await reopenViaProvider(dbPath);
    expect(await db.getVersion(), DbProvider.dbVersion);
    for (final table in DbConstants.syncedTables) {
      expect(await tableCount(db, table), before[table], reason: table);
      for (final row in await db.query(table)) {
        expect(
          row.containsKey(DbConstants.columnRemoteId),
          isTrue,
          reason: table,
        );
      }
    }
    await db.close();
  });

  test('corrupt file is rejected and live db is untouched', () async {
    final db = await openFreshTestDb();
    final dbPath = db.path;
    await _insertSampleRows(db);

    final dir = await _tempDir('i_gen_backup_corrupt_test');
    final corruptPath = p.join(dir.path, 'corrupt.db');
    await File(
      corruptPath,
    ).writeAsBytes(List<int>.generate(256, (i) => (i * 7 + 3) % 256));
    final service = BackupService(db: db, dbPath: dbPath, appDocDir: dir.path);

    expect(
      () => BackupService.validateBackupFile(corruptPath),
      throwsA(isA<StateError>()),
    );
    expect(
      () => service.restoreFromFile(corruptPath),
      throwsA(isA<StateError>()),
    );

    // No fallback was created and the live rows are intact.
    expect(await File('$dbPath.pre-restore').exists(), isFalse);
    expect(await tableCount(db, DbConstants.tableProduct), 1);
    expect(await tableCount(db, DbConstants.tableOutbox), 1);
    await db.close();
  });

  test('auto-backup writes once per 7 days and prunes to newest 3', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await openFreshTestDb();
    final appDir = await _tempDir('i_gen_auto_backup_test');
    final service = BackupService(
      db: db,
      dbPath: db.path,
      appDocDir: appDir.path,
    );

    expect(await service.lastAutoBackupAt(prefs), isNull);
    await service.maybeAutoBackup(prefs);
    expect(_autoBackups(appDir), hasLength(1));
    expect(await service.lastAutoBackupAt(prefs), isNotNull);

    // Still fresh: no second file.
    await service.maybeAutoBackup(prefs);
    expect(_autoBackups(appDir), hasLength(1));

    // Stale stamp plus old dummies: a new backup is written and only the
    // newest 3 files survive.
    await prefs.setInt(
      BackupService.lastAutoBackupKey,
      DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch,
    );
    for (var i = 1; i <= 4; i++) {
      await File(
        p.join(appDir.path, 'auto-backup-2020010$i-0000.db'),
      ).writeAsString('stale-$i');
    }
    await service.maybeAutoBackup(prefs);
    final kept = _autoBackups(appDir)..sort((a, b) => a.path.compareTo(b.path));
    expect(kept, hasLength(3));
    expect(p.basename(kept[0].path), 'auto-backup-20200103-0000.db');
    expect(p.basename(kept[1].path), 'auto-backup-20200104-0000.db');
    // The real backup (today's stamp) is the newest and must validate.
    await BackupService.validateBackupFile(kept[2].path);
    final stamp = await service.lastAutoBackupAt(prefs);
    expect(DateTime.now().difference(stamp!).inMinutes, lessThan(10));
    await db.close();
  });

  test(
    'auto-backup off writes nothing and custom interval is honored',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = await openFreshTestDb();
      final appDir = await _tempDir('i_gen_auto_backup_interval_test');
      final service = BackupService(
        db: db,
        dbPath: db.path,
        appDocDir: appDir.path,
      );

      // Off: no file, no stamp.
      await prefs.setInt(BackupService.autoIntervalDaysKey, 0);
      await service.maybeAutoBackup(prefs);
      expect(_autoBackups(appDir), isEmpty);
      expect(await service.lastAutoBackupAt(prefs), isNull);

      // Daily: stale-by-2-days stamp triggers a run.
      await prefs.setInt(BackupService.autoIntervalDaysKey, 1);
      await prefs.setInt(
        BackupService.lastAutoBackupKey,
        DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch,
      );
      await service.maybeAutoBackup(prefs);
      expect(_autoBackups(appDir), hasLength(1));
      await db.close();
    },
  );
}
