import 'package:sqflite/sqflite.dart';
import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/sync/sync_models.dart';

class SyncRepository {
  final Database db;

  const SyncRepository(this.db);

  // ==================== EXPORT ====================

  /// Get all changes since the given timestamp
  Future<SyncPayload> getChangesSince(
    int anchor,
    String deviceId,
    String deviceName,
  ) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    return SyncPayload(
      sourceDeviceId: deviceId,
      sourceDeviceName: deviceName,
      timestamp: now,
      products: await _getTableChanges(DbConstants.tableProduct, anchor),
      invoices: await _getInvoicesWithLines(anchor),
      priceCategories: await _getTableChanges(
        DbConstants.tablePriceCategory,
        anchor,
      ),
      prices: await _getTableChanges(DbConstants.tablePrices, anchor),
      tombstones: await _getTombstones(anchor),
    );
  }

  Future<List<Map<String, dynamic>>> _getTableChanges(
    String table,
    int anchor,
  ) async {
    final rows = await db.query(
      table,
      where: '${DbConstants.columnUpdatedAt} > ?',
      whereArgs: [anchor],
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> _getInvoicesWithLines(int anchor) async {
    // Get changed invoices
    final invoices = await db.query(
      DbConstants.tableInvoice,
      where: '${DbConstants.columnUpdatedAt} > ?',
      whereArgs: [anchor],
    );

    final result = <Map<String, dynamic>>[];

    for (final invoice in invoices) {
      final invoiceId = invoice[DbConstants.columnId] as int;
      final invoiceUuid = invoice[DbConstants.columnUuid] as String?;

      // Get lines for this invoice
      final lines = await db.rawQuery(
        '''
        SELECT 
          il.${DbConstants.columnUuid} as uuid,
          il.${DbConstants.columnUpdatedAt} as updated_at,
          il.${DbConstants.columnInvoiceLineAmount} as amount,
          il.${DbConstants.columnInvoiceLinePrice} as price,
          p.${DbConstants.columnUuid} as product_uuid
        FROM ${DbConstants.tableInvoiceLine} il
        JOIN ${DbConstants.tableProduct} p ON il.${DbConstants.columnInvoiceLineProductId} = p.${DbConstants.columnId}
        WHERE il.${DbConstants.columnInvoiceLineInvoiceId} = ?
      ''',
        [invoiceId],
      );

      result.add({
        ...invoice,
        'lines': lines.map((l) => {...l, 'invoice_uuid': invoiceUuid}).toList(),
      });
    }

    return result;
  }

  Future<List<Tombstone>> _getTombstones(int anchor) async {
    final rows = await db.query(
      DbConstants.tableSyncTombstones,
      where: 'deleted_at > ?',
      whereArgs: [anchor],
    );
    return rows
        .map(
          (r) => Tombstone(
            tableName: r['table_name'] as String,
            uuid: r['uuid'] as String,
            deletedAt: r['deleted_at'] as int,
          ),
        )
        .toList();
  }

  // ==================== IMPORT ====================

  /// Merge incoming sync payload
  Future<SyncResult> mergePayload(SyncPayload payload) async {
    var result = const SyncResult();

    return await db.transaction((txn) async {
      // Order matters: products before invoices (FK dependency)
      result = result + await _mergeProducts(txn, payload.products);
      result =
          result + await _mergePriceCategories(txn, payload.priceCategories);
      result = result + await _mergePrices(txn, payload.prices);
      result = result + await _mergeInvoices(txn, payload.invoices);
      result = result + await _applyTombstones(txn, payload.tombstones);

      // Update sync history
      await _updateSyncHistory(
        txn,
        payload.sourceDeviceId,
        payload.sourceDeviceName,
      );

      return result;
    });
  }

  Future<SyncResult> _mergeProducts(
    Transaction txn,
    List<Map<String, dynamic>> products,
  ) async {
    int inserted = 0, updated = 0, skipped = 0;

    for (final remote in products) {
      final uuid = remote['uuid'] as String;
      final remoteUpdatedAt = remote['updated_at'] as int;

      final existing = await txn.query(
        DbConstants.tableProduct,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: [uuid],
      );

      if (existing.isEmpty) {
        // Insert new
        await txn.insert(DbConstants.tableProduct, {
          DbConstants.columnProductModel: remote['model'],
          DbConstants.columnProductName: remote['name'],
          DbConstants.columnUuid: uuid,
          DbConstants.columnUpdatedAt: remoteUpdatedAt,
        });
        inserted++;
      } else {
        final localUpdatedAt =
            existing.first[DbConstants.columnUpdatedAt] as int? ?? 0;
        if (remoteUpdatedAt > localUpdatedAt) {
          // Update existing
          await txn.update(
            DbConstants.tableProduct,
            {
              DbConstants.columnProductModel: remote['model'],
              DbConstants.columnProductName: remote['name'],
              DbConstants.columnUpdatedAt: remoteUpdatedAt,
            },
            where: '${DbConstants.columnUuid} = ?',
            whereArgs: [uuid],
          );
          updated++;
        } else {
          skipped++;
        }
      }
    }

    return SyncResult(inserted: inserted, updated: updated, skipped: skipped);
  }

  Future<SyncResult> _mergePriceCategories(
    Transaction txn,
    List<Map<String, dynamic>> categories,
  ) async {
    int inserted = 0, updated = 0, skipped = 0;

    for (final remote in categories) {
      final uuid = remote['uuid'] as String;
      final remoteUpdatedAt = remote['updated_at'] as int;

      final existing = await txn.query(
        DbConstants.tablePriceCategory,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: [uuid],
      );

      if (existing.isEmpty) {
        await txn.insert(DbConstants.tablePriceCategory, {
          DbConstants.columnPriceCategoryName: remote['name'],
          DbConstants.columnPriceCategoryCurrency: remote['currency'],
          DbConstants.columnUuid: uuid,
          DbConstants.columnUpdatedAt: remoteUpdatedAt,
        });
        inserted++;
      } else {
        final localUpdatedAt =
            existing.first[DbConstants.columnUpdatedAt] as int? ?? 0;
        if (remoteUpdatedAt > localUpdatedAt) {
          await txn.update(
            DbConstants.tablePriceCategory,
            {
              DbConstants.columnPriceCategoryName: remote['name'],
              DbConstants.columnPriceCategoryCurrency: remote['currency'],
              DbConstants.columnUpdatedAt: remoteUpdatedAt,
            },
            where: '${DbConstants.columnUuid} = ?',
            whereArgs: [uuid],
          );
          updated++;
        } else {
          skipped++;
        }
      }
    }

    return SyncResult(inserted: inserted, updated: updated, skipped: skipped);
  }

  Future<SyncResult> _mergePrices(
    Transaction txn,
    List<Map<String, dynamic>> prices,
  ) async {
    int inserted = 0, updated = 0, skipped = 0;
    final errors = <String>[];

    for (final remote in prices) {
      final uuid = remote['uuid'] as String;
      final remoteUpdatedAt = remote['updated_at'] as int;

      // Resolve product_id from uuid (stored in remote as foreign reference)
      final productId = await _resolveProductId(txn, remote);
      final categoryId = await _resolveCategoryId(txn, remote);

      if (productId == null || categoryId == null) {
        errors.add('Price $uuid: Could not resolve product or category');
        continue;
      }

      final existing = await txn.query(
        DbConstants.tablePrices,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: [uuid],
      );

      if (existing.isEmpty) {
        await txn.insert(DbConstants.tablePrices, {
          DbConstants.columnPricesProductId: productId,
          DbConstants.columnPricesPriceCategoryId: categoryId,
          DbConstants.columnPricesPrice: remote['price'],
          DbConstants.columnUuid: uuid,
          DbConstants.columnUpdatedAt: remoteUpdatedAt,
        });
        inserted++;
      } else {
        final localUpdatedAt =
            existing.first[DbConstants.columnUpdatedAt] as int? ?? 0;
        if (remoteUpdatedAt > localUpdatedAt) {
          await txn.update(
            DbConstants.tablePrices,
            {
              DbConstants.columnPricesProductId: productId,
              DbConstants.columnPricesPriceCategoryId: categoryId,
              DbConstants.columnPricesPrice: remote['price'],
              DbConstants.columnUpdatedAt: remoteUpdatedAt,
            },
            where: '${DbConstants.columnUuid} = ?',
            whereArgs: [uuid],
          );
          updated++;
        } else {
          skipped++;
        }
      }
    }

    return SyncResult(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  Future<SyncResult> _mergeInvoices(
    Transaction txn,
    List<Map<String, dynamic>> invoices,
  ) async {
    int inserted = 0, updated = 0, skipped = 0;

    for (final remote in invoices) {
      final uuid = remote['uuid'] as String;
      final remoteUpdatedAt = remote['updated_at'] as int;

      final existing = await txn.query(
        DbConstants.tableInvoice,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: [uuid],
      );

      int invoiceId;

      if (existing.isEmpty) {
        // Insert new invoice
        invoiceId = await txn.insert(DbConstants.tableInvoice, {
          DbConstants.columnCustomerName: remote['customer'],
          DbConstants.columnInvoiceDate: remote['date'],
          DbConstants.columnInvoiceTotal: remote['total'],
          DbConstants.columnInvoiceCurrency: remote['currency'],
          DbConstants.columnInvoiceDiscount: remote['discount'] ?? 0,
          DbConstants.columnUuid: uuid,
          DbConstants.columnUpdatedAt: remoteUpdatedAt,
        });
        inserted++;
      } else {
        final localUpdatedAt =
            existing.first[DbConstants.columnUpdatedAt] as int? ?? 0;
        invoiceId = existing.first[DbConstants.columnId] as int;

        if (remoteUpdatedAt > localUpdatedAt) {
          await txn.update(
            DbConstants.tableInvoice,
            {
              DbConstants.columnCustomerName: remote['customer'],
              DbConstants.columnInvoiceDate: remote['date'],
              DbConstants.columnInvoiceTotal: remote['total'],
              DbConstants.columnInvoiceDiscount: remote['discount'] ?? 0,
              DbConstants.columnUpdatedAt: remoteUpdatedAt,
            },
            where: '${DbConstants.columnUuid} = ?',
            whereArgs: [uuid],
          );
          updated++;
        } else {
          skipped++;
          continue; // Skip lines if invoice wasn't updated
        }
      }

      // Merge invoice lines
      final lines = remote['lines'] as List<dynamic>? ?? [];
      await _mergeInvoiceLines(txn, invoiceId, uuid, lines);
    }

    return SyncResult(inserted: inserted, updated: updated, skipped: skipped);
  }

  Future<void> _mergeInvoiceLines(
    Transaction txn,
    int invoiceId,
    String invoiceUuid,
    List<dynamic> lines,
  ) async {
    for (final line in lines) {
      final lineData = line as Map<String, dynamic>;
      final lineUuid = lineData['uuid'] as String;
      final lineUpdatedAt = lineData['updated_at'] as int;

      // Resolve product ID
      final productUuid = lineData['product_uuid'] as String?;
      int? productId;
      if (productUuid != null) {
        final product = await txn.query(
          DbConstants.tableProduct,
          columns: [DbConstants.columnId],
          where: '${DbConstants.columnUuid} = ?',
          whereArgs: [productUuid],
        );
        productId = product.isNotEmpty
            ? product.first[DbConstants.columnId] as int
            : null;
      }

      if (productId == null) continue; // Skip if product not found

      final existing = await txn.query(
        DbConstants.tableInvoiceLine,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: [lineUuid],
      );

      if (existing.isEmpty) {
        await txn.insert(DbConstants.tableInvoiceLine, {
          DbConstants.columnInvoiceLineInvoiceId: invoiceId,
          DbConstants.columnInvoiceLineProductId: productId,
          DbConstants.columnInvoiceLineAmount: lineData['amount'],
          DbConstants.columnInvoiceLinePrice: lineData['price'],
          DbConstants.columnUuid: lineUuid,
          DbConstants.columnUpdatedAt: lineUpdatedAt,
        });
      } else {
        final localUpdatedAt =
            existing.first[DbConstants.columnUpdatedAt] as int? ?? 0;
        if (lineUpdatedAt > localUpdatedAt) {
          await txn.update(
            DbConstants.tableInvoiceLine,
            {
              DbConstants.columnInvoiceLineProductId: productId,
              DbConstants.columnInvoiceLineAmount: lineData['amount'],
              DbConstants.columnInvoiceLinePrice: lineData['price'],
              DbConstants.columnUpdatedAt: lineUpdatedAt,
            },
            where: '${DbConstants.columnUuid} = ?',
            whereArgs: [lineUuid],
          );
        }
      }
    }
  }

  Future<SyncResult> _applyTombstones(
    Transaction txn,
    List<Tombstone> tombstones,
  ) async {
    int deleted = 0;

    for (final tombstone in tombstones) {
      final result = await txn.delete(
        tombstone.tableName,
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: [tombstone.uuid],
      );
      if (result > 0) deleted++;
    }

    return SyncResult(deleted: deleted);
  }

  Future<int?> _resolveProductId(
    Transaction txn,
    Map<String, dynamic> remote,
  ) async {
    // Check if remote contains product_uuid or direct product_id
    final productUuid = remote['product_uuid'] as String?;
    if (productUuid == null) return null;

    final result = await txn.query(
      DbConstants.tableProduct,
      columns: [DbConstants.columnId],
      where: '${DbConstants.columnUuid} = ?',
      whereArgs: [productUuid],
    );
    return result.isNotEmpty ? result.first[DbConstants.columnId] as int : null;
  }

  Future<int?> _resolveCategoryId(
    Transaction txn,
    Map<String, dynamic> remote,
  ) async {
    final categoryUuid = remote['category_uuid'] as String?;
    if (categoryUuid == null) return null;

    final result = await txn.query(
      DbConstants.tablePriceCategory,
      columns: [DbConstants.columnId],
      where: '${DbConstants.columnUuid} = ?',
      whereArgs: [categoryUuid],
    );
    return result.isNotEmpty ? result.first[DbConstants.columnId] as int : null;
  }

  Future<void> _updateSyncHistory(
    Transaction txn,
    String deviceId,
    String deviceName,
  ) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await txn.insert(DbConstants.tableSyncHistory, {
      'device_id': deviceId,
      'device_name': deviceName,
      'last_sync_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==================== TOMBSTONES ====================

  /// Record a deletion
  Future<void> recordDeletion(String tableName, String uuid) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.insert(
      DbConstants.tableSyncTombstones,
      {'table_name': tableName, 'uuid': uuid, 'deleted_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ==================== SYNC HISTORY ====================

  /// Get last sync time for a device
  Future<int> getLastSyncAnchor(String deviceId) async {
    final result = await db.query(
      DbConstants.tableSyncHistory,
      columns: ['last_sync_at'],
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
    return result.isNotEmpty ? result.first['last_sync_at'] as int : 0;
  }

  /// Get all known devices
  Future<List<Map<String, dynamic>>> getSyncHistory() async {
    return await db.query(
      DbConstants.tableSyncHistory,
      orderBy: 'last_sync_at DESC',
    );
  }
}
