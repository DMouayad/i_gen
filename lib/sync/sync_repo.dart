import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/sync/sync_models.dart';

class SyncRepository {
  final Database db;

  const SyncRepository(this.db);

  // ==================== EXPORT ====================
  // Update the getChangesSince method to handle prices specially
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
      prices: await _getPricesWithRefs(anchor), // Changed
      tombstones: await _getTombstones(anchor),
    );
  }

  void _log(String message) {
    if (kDebugMode) {
      print('[SYNC] $message');
    }
  }

  // Update _getPricesWithRefs to log what's being exported
  Future<List<Map<String, dynamic>>> _getPricesWithRefs(int anchor) async {
    _log('📤 Exporting prices changed since anchor: $anchor');

    final rows = await db.rawQuery(
      '''
    SELECT 
      prices.*,
      product.uuid AS product_uuid,
      product.model AS product_model,
      price_category.uuid AS category_uuid,
      price_category.name AS category_name
    FROM ${DbConstants.tablePrices} prices
    JOIN ${DbConstants.tableProduct} product 
      ON prices.${DbConstants.columnPricesProductId} = product.${DbConstants.columnId}
    JOIN ${DbConstants.tablePriceCategory} price_category 
      ON prices.${DbConstants.columnPricesPriceCategoryId} = price_category.${DbConstants.columnId}
    WHERE prices.${DbConstants.columnUpdatedAt} > ?
  ''',
      [anchor],
    );

    _log('📤 Found ${rows.length} prices to export');

    for (final row in rows) {
      _log(
        '📤 Price: product=${row['product_model']}, '
        'category=${row['category_name']}, '
        'price=${row[DbConstants.columnPricesPrice]}, '
        'updated_at=${row[DbConstants.columnUpdatedAt]}, '
        'uuid=${row['uuid']}',
      );
    }

    return rows
        .map(
          (row) => {
            'uuid': row['uuid'],
            'price': row[DbConstants.columnPricesPrice],
            'product_uuid': row['product_uuid'],
            'product_model': row['product_model'],
            'category_uuid': row['category_uuid'],
            'category_name': row['category_name'],
            'updated_at': row[DbConstants.columnUpdatedAt],
          },
        )
        .toList();
  }

  // Update _mergePrices with detailed logging
  Future<SyncResult> _mergePrices(
    Transaction txn,
    List<Map<String, dynamic>> prices,
  ) async {
    int inserted = 0, updated = 0, skipped = 0;
    final errors = <String>[];

    _log('📥 Merging ${prices.length} prices');

    for (final remote in prices) {
      final uuid = remote['uuid'] as String?;
      final remoteUpdatedAt = remote['updated_at'] as int? ?? 0;
      final price = remote['price'];
      final productUuid = remote['product_uuid'] as String?;
      final productModel = remote['product_model'] as String?;
      final categoryUuid = remote['category_uuid'] as String?;
      final categoryName = remote['category_name'] as String?;

      _log(
        '📥 Processing price: product=$productModel, category=$categoryName, '
        'price=$price, updated_at=$remoteUpdatedAt',
      );

      if (uuid == null) {
        _log('❌ Skipping: missing uuid');
        errors.add('Price missing uuid');
        continue;
      }

      try {
        // Resolve foreign keys
        final productId = await _resolveProductId(txn, remote);
        final categoryId = await _resolveCategoryId(txn, remote);

        _log('   Resolved: productId=$productId, categoryId=$categoryId');

        if (productId == null) {
          _log(
            '❌ Could not resolve product (uuid=$productUuid, model=$productModel)',
          );
          errors.add('Price $uuid: Could not resolve product');
          continue;
        }

        if (categoryId == null) {
          _log(
            '❌ Could not resolve category (uuid=$categoryUuid, name=$categoryName)',
          );
          errors.add('Price $uuid: Could not resolve category');
          continue;
        }

        // Check by UUID
        final existingByUuid = await txn.query(
          DbConstants.tablePrices,
          where: '${DbConstants.columnUuid} = ?',
          whereArgs: [uuid],
        );

        if (existingByUuid.isNotEmpty) {
          final localUpdatedAt =
              existingByUuid.first[DbConstants.columnUpdatedAt] as int? ?? 0;
          final localPrice =
              existingByUuid.first[DbConstants.columnPricesPrice];

          _log(
            '   Found by UUID: local_updated_at=$localUpdatedAt, local_price=$localPrice',
          );

          if (remoteUpdatedAt > localUpdatedAt) {
            await txn.update(
              DbConstants.tablePrices,
              {
                DbConstants.columnPricesProductId: productId,
                DbConstants.columnPricesPriceCategoryId: categoryId,
                DbConstants.columnPricesPrice: price,
                DbConstants.columnUpdatedAt: remoteUpdatedAt,
              },
              where: '${DbConstants.columnUuid} = ?',
              whereArgs: [uuid],
            );
            _log('✅ Updated by UUID (remote is newer)');
            updated++;
          } else {
            _log('⏭️ Skipped (local is newer or equal)');
            skipped++;
          }
          continue;
        }

        // Check by composite key (product_id, category_id)
        final existingByKey = await txn.query(
          DbConstants.tablePrices,
          where:
              '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
          whereArgs: [productId, categoryId],
        );

        if (existingByKey.isNotEmpty) {
          final localUpdatedAt =
              existingByKey.first[DbConstants.columnUpdatedAt] as int? ?? 0;
          final localPrice = existingByKey.first[DbConstants.columnPricesPrice];
          final localUuid = existingByKey.first['uuid'];

          _log(
            '   Found by key: local_uuid=$localUuid, local_updated_at=$localUpdatedAt, local_price=$localPrice',
          );

          if (remoteUpdatedAt > localUpdatedAt) {
            await txn.update(
              DbConstants.tablePrices,
              {
                DbConstants.columnPricesPrice: price,
                DbConstants.columnUuid: uuid,
                DbConstants.columnUpdatedAt: remoteUpdatedAt,
              },
              where:
                  '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
              whereArgs: [productId, categoryId],
            );
            _log('✅ Updated by key (remote is newer)');
            updated++;
          } else {
            _log('⏭️ Skipped (local is newer or equal)');
            skipped++;
          }
          continue;
        }

        // Insert new
        _log('   No existing record found, inserting new');
        await txn.insert(DbConstants.tablePrices, {
          DbConstants.columnPricesProductId: productId,
          DbConstants.columnPricesPriceCategoryId: categoryId,
          DbConstants.columnPricesPrice: price,
          DbConstants.columnUuid: uuid,
          DbConstants.columnUpdatedAt: remoteUpdatedAt,
        });
        _log('✅ Inserted new price');
        inserted++;
      } catch (e, stack) {
        _log('❌ Error: $e');
        _log('   Stack: ${stack.toString().split('\n').take(3).join('\n')}');
        errors.add('Price $uuid: $e');
      }
    }

    _log(
      '📥 Price merge complete: inserted=$inserted, updated=$updated, skipped=$skipped, errors=${errors.length}',
    );

    return SyncResult(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  // Update resolver methods with logging
  Future<int?> _resolveProductId(
    Transaction txn,
    Map<String, dynamic> remote,
  ) async {
    final productUuid = remote['product_uuid'] as String?;
    final productModel = remote['product_model'] as String?;

    // 1. Try by UUID
    if (productUuid != null && productUuid.isNotEmpty) {
      final result = await txn.query(
        DbConstants.tableProduct,
        columns: [DbConstants.columnId, DbConstants.columnProductModel],
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: [productUuid],
      );
      if (result.isNotEmpty) {
        _log(
          '   Product resolved by UUID: $productUuid -> id=${result.first[DbConstants.columnId]}',
        );
        return result.first[DbConstants.columnId] as int;
      }
      _log('   Product UUID not found: $productUuid');
    }

    // 2. Fallback to model
    if (productModel != null && productModel.isNotEmpty) {
      final result = await txn.query(
        DbConstants.tableProduct,
        columns: [DbConstants.columnId],
        where: '${DbConstants.columnProductModel} = ?',
        whereArgs: [productModel],
      );
      if (result.isNotEmpty) {
        _log(
          '   Product resolved by model: $productModel -> id=${result.first[DbConstants.columnId]}',
        );
        return result.first[DbConstants.columnId] as int;
      }
      _log('   Product model not found: $productModel');
    }

    return null;
  }

  Future<int?> _resolveCategoryId(
    Transaction txn,
    Map<String, dynamic> remote,
  ) async {
    final categoryUuid = remote['category_uuid'] as String?;
    final categoryName = remote['category_name'] as String?;

    // 1. Try by UUID
    if (categoryUuid != null && categoryUuid.isNotEmpty) {
      final result = await txn.query(
        DbConstants.tablePriceCategory,
        columns: [DbConstants.columnId, DbConstants.columnPriceCategoryName],
        where: '${DbConstants.columnUuid} = ?',
        whereArgs: [categoryUuid],
      );
      if (result.isNotEmpty) {
        _log(
          '   Category resolved by UUID: $categoryUuid -> id=${result.first[DbConstants.columnId]}',
        );
        return result.first[DbConstants.columnId] as int;
      }
      _log('   Category UUID not found: $categoryUuid');
    }

    // 2. Fallback to name
    if (categoryName != null && categoryName.isNotEmpty) {
      final result = await txn.query(
        DbConstants.tablePriceCategory,
        columns: [DbConstants.columnId],
        where: '${DbConstants.columnPriceCategoryName} = ?',
        whereArgs: [categoryName],
      );
      if (result.isNotEmpty) {
        _log(
          '   Category resolved by name: $categoryName -> id=${result.first[DbConstants.columnId]}',
        );
        return result.first[DbConstants.columnId] as int;
      }
      _log('   Category name not found: $categoryName');
    }

    return null;
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

  // lib/sync/sync_repository.dart

  Future<SyncResult> _mergeProducts(
    Transaction txn,
    List<Map<String, dynamic>> products,
  ) async {
    int inserted = 0, updated = 0, skipped = 0;
    final errors = <String>[];

    for (final remote in products) {
      final uuid = remote['uuid'] as String?;
      final model = remote['model'] as String?;
      final name = remote['name'] as String?;
      final remoteUpdatedAt = remote['updated_at'] as int? ?? 0;

      if (uuid == null || model == null || name == null) {
        errors.add('Product missing required fields');
        continue;
      }

      try {
        // First, check if product exists by UUID
        final existingByUuid = await txn.query(
          DbConstants.tableProduct,
          where: '${DbConstants.columnUuid} = ?',
          whereArgs: [uuid],
        );

        if (existingByUuid.isNotEmpty) {
          // UUID exists - check if we should update
          final localUpdatedAt =
              existingByUuid.first[DbConstants.columnUpdatedAt] as int? ?? 0;
          if (remoteUpdatedAt > localUpdatedAt) {
            await txn.update(
              DbConstants.tableProduct,
              {
                DbConstants.columnProductModel: model,
                DbConstants.columnProductName: name,
                DbConstants.columnUpdatedAt: remoteUpdatedAt,
              },
              where: '${DbConstants.columnUuid} = ?',
              whereArgs: [uuid],
            );
            updated++;
          } else {
            skipped++;
          }
          continue;
        }

        // UUID doesn't exist - check if model exists (conflict)
        final existingByModel = await txn.query(
          DbConstants.tableProduct,
          where: '${DbConstants.columnProductModel} = ?',
          whereArgs: [model],
        );

        if (existingByModel.isNotEmpty) {
          // Model exists with different UUID - resolve conflict
          final localUpdatedAt =
              existingByModel.first[DbConstants.columnUpdatedAt] as int? ?? 0;

          if (remoteUpdatedAt > localUpdatedAt) {
            // Remote is newer - update existing record with new UUID
            await txn.update(
              DbConstants.tableProduct,
              {
                DbConstants.columnProductName: name,
                DbConstants.columnUuid: uuid, // Take remote UUID
                DbConstants.columnUpdatedAt: remoteUpdatedAt,
              },
              where: '${DbConstants.columnProductModel} = ?',
              whereArgs: [model],
            );
            updated++;
          } else {
            // Local is newer - skip
            skipped++;
          }
          continue;
        }

        // Neither UUID nor model exists - insert new
        await txn.insert(DbConstants.tableProduct, {
          DbConstants.columnProductModel: model,
          DbConstants.columnProductName: name,
          DbConstants.columnUuid: uuid,
          DbConstants.columnUpdatedAt: remoteUpdatedAt,
        });
        inserted++;
      } catch (e) {
        errors.add('Product $model: $e');
      }
    }

    return SyncResult(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  Future<SyncResult> _mergePriceCategories(
    Transaction txn,
    List<Map<String, dynamic>> categories,
  ) async {
    int inserted = 0, updated = 0, skipped = 0;
    final errors = <String>[];

    for (final remote in categories) {
      final uuid = remote['uuid'] as String?;
      final name = remote['name'] as String?;
      final currency = remote['currency'] as String?;
      final remoteUpdatedAt = remote['updated_at'] as int? ?? 0;

      if (uuid == null || name == null || currency == null) {
        errors.add('Price category missing required fields');
        continue;
      }

      try {
        // Check by UUID first
        final existingByUuid = await txn.query(
          DbConstants.tablePriceCategory,
          where: '${DbConstants.columnUuid} = ?',
          whereArgs: [uuid],
        );

        if (existingByUuid.isNotEmpty) {
          final localUpdatedAt =
              existingByUuid.first[DbConstants.columnUpdatedAt] as int? ?? 0;
          if (remoteUpdatedAt > localUpdatedAt) {
            await txn.update(
              DbConstants.tablePriceCategory,
              {
                DbConstants.columnPriceCategoryName: name,
                DbConstants.columnPriceCategoryCurrency: currency,
                DbConstants.columnUpdatedAt: remoteUpdatedAt,
              },
              where: '${DbConstants.columnUuid} = ?',
              whereArgs: [uuid],
            );
            updated++;
          } else {
            skipped++;
          }
          continue;
        }

        // Check by name (unique constraint)
        final existingByName = await txn.query(
          DbConstants.tablePriceCategory,
          where: '${DbConstants.columnPriceCategoryName} = ?',
          whereArgs: [name],
        );

        if (existingByName.isNotEmpty) {
          final localUpdatedAt =
              existingByName.first[DbConstants.columnUpdatedAt] as int? ?? 0;
          if (remoteUpdatedAt > localUpdatedAt) {
            await txn.update(
              DbConstants.tablePriceCategory,
              {
                DbConstants.columnPriceCategoryCurrency: currency,
                DbConstants.columnUuid: uuid,
                DbConstants.columnUpdatedAt: remoteUpdatedAt,
              },
              where: '${DbConstants.columnPriceCategoryName} = ?',
              whereArgs: [name],
            );
            updated++;
          } else {
            skipped++;
          }
          continue;
        }

        // Insert new
        await txn.insert(DbConstants.tablePriceCategory, {
          DbConstants.columnPriceCategoryName: name,
          DbConstants.columnPriceCategoryCurrency: currency,
          DbConstants.columnUuid: uuid,
          DbConstants.columnUpdatedAt: remoteUpdatedAt,
        });
        inserted++;
      } catch (e) {
        errors.add('Price category $name: $e');
      }
    }

    return SyncResult(
      inserted: inserted,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  // Future<SyncResult> _mergePrices(
  //   Transaction txn,
  //   List<Map<String, dynamic>> prices,
  // ) async {
  //   int inserted = 0, updated = 0, skipped = 0;
  //   final errors = <String>[];

  //   for (final remote in prices) {
  //     final uuid = remote['uuid'] as String?;
  //     final remoteUpdatedAt = remote['updated_at'] as int? ?? 0;
  //     final price = remote['price'];

  //     if (uuid == null) {
  //       errors.add('Price missing uuid');
  //       continue;
  //     }

  //     try {
  //       // Resolve foreign keys
  //       final productId = await _resolveProductId(txn, remote);
  //       final categoryId = await _resolveCategoryId(txn, remote);

  //       if (productId == null || categoryId == null) {
  //         errors.add('Price $uuid: Could not resolve product or category');
  //         continue;
  //       }

  //       // Check by UUID
  //       final existingByUuid = await txn.query(
  //         DbConstants.tablePrices,
  //         where: '${DbConstants.columnUuid} = ?',
  //         whereArgs: [uuid],
  //       );

  //       if (existingByUuid.isNotEmpty) {
  //         final localUpdatedAt =
  //             existingByUuid.first[DbConstants.columnUpdatedAt] as int? ?? 0;
  //         if (remoteUpdatedAt > localUpdatedAt) {
  //           await txn.update(
  //             DbConstants.tablePrices,
  //             {
  //               DbConstants.columnPricesProductId: productId,
  //               DbConstants.columnPricesPriceCategoryId: categoryId,
  //               DbConstants.columnPricesPrice: price,
  //               DbConstants.columnUpdatedAt: remoteUpdatedAt,
  //             },
  //             where: '${DbConstants.columnUuid} = ?',
  //             whereArgs: [uuid],
  //           );
  //           updated++;
  //         } else {
  //           skipped++;
  //         }
  //         continue;
  //       }

  //       // Check by composite key (product_id, category_id)
  //       final existingByKey = await txn.query(
  //         DbConstants.tablePrices,
  //         where:
  //             '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
  //         whereArgs: [productId, categoryId],
  //       );

  //       if (existingByKey.isNotEmpty) {
  //         final localUpdatedAt =
  //             existingByKey.first[DbConstants.columnUpdatedAt] as int? ?? 0;
  //         if (remoteUpdatedAt > localUpdatedAt) {
  //           await txn.update(
  //             DbConstants.tablePrices,
  //             {
  //               DbConstants.columnPricesPrice: price,
  //               DbConstants.columnUuid: uuid,
  //               DbConstants.columnUpdatedAt: remoteUpdatedAt,
  //             },
  //             where:
  //                 '${DbConstants.columnPricesProductId} = ? AND ${DbConstants.columnPricesPriceCategoryId} = ?',
  //             whereArgs: [productId, categoryId],
  //           );
  //           updated++;
  //         } else {
  //           skipped++;
  //         }
  //         continue;
  //       }

  //       // Insert new
  //       await txn.insert(DbConstants.tablePrices, {
  //         DbConstants.columnPricesProductId: productId,
  //         DbConstants.columnPricesPriceCategoryId: categoryId,
  //         DbConstants.columnPricesPrice: price,
  //         DbConstants.columnUuid: uuid,
  //         DbConstants.columnUpdatedAt: remoteUpdatedAt,
  //       });
  //       inserted++;
  //     } catch (e) {
  //       errors.add('Price $uuid: $e');
  //     }
  //   }

  //   return SyncResult(
  //     inserted: inserted,
  //     updated: updated,
  //     skipped: skipped,
  //     errors: errors,
  //   );
  // }

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
      final lineUuid = lineData['uuid'] as String?;
      final lineUpdatedAt = lineData['updated_at'] as int? ?? 0;

      if (lineUuid == null) continue;

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

      if (productId == null) continue;

      try {
        // Check by UUID
        final existingByUuid = await txn.query(
          DbConstants.tableInvoiceLine,
          where: '${DbConstants.columnUuid} = ?',
          whereArgs: [lineUuid],
        );

        if (existingByUuid.isNotEmpty) {
          final localUpdatedAt =
              existingByUuid.first[DbConstants.columnUpdatedAt] as int? ?? 0;
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
          continue;
        }

        // Check by composite key (invoice_id, product_id)
        final existingByKey = await txn.query(
          DbConstants.tableInvoiceLine,
          where:
              '${DbConstants.columnInvoiceLineInvoiceId} = ? AND ${DbConstants.columnInvoiceLineProductId} = ?',
          whereArgs: [invoiceId, productId],
        );

        if (existingByKey.isNotEmpty) {
          final localUpdatedAt =
              existingByKey.first[DbConstants.columnUpdatedAt] as int? ?? 0;
          if (lineUpdatedAt > localUpdatedAt) {
            await txn.update(
              DbConstants.tableInvoiceLine,
              {
                DbConstants.columnInvoiceLineAmount: lineData['amount'],
                DbConstants.columnInvoiceLinePrice: lineData['price'],
                DbConstants.columnUuid: lineUuid,
                DbConstants.columnUpdatedAt: lineUpdatedAt,
              },
              where:
                  '${DbConstants.columnInvoiceLineInvoiceId} = ? AND ${DbConstants.columnInvoiceLineProductId} = ?',
              whereArgs: [invoiceId, productId],
            );
          }
          continue;
        }

        // Insert new
        await txn.insert(DbConstants.tableInvoiceLine, {
          DbConstants.columnInvoiceLineInvoiceId: invoiceId,
          DbConstants.columnInvoiceLineProductId: productId,
          DbConstants.columnInvoiceLineAmount: lineData['amount'],
          DbConstants.columnInvoiceLinePrice: lineData['price'],
          DbConstants.columnUuid: lineUuid,
          DbConstants.columnUpdatedAt: lineUpdatedAt,
        });
      } catch (e) {
        print('Error merging invoice line: $e');
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

  // Future<int?> _resolveProductId(
  //   Transaction txn,
  //   Map<String, dynamic> remote,
  // ) async {
  //   // Check if remote contains product_uuid or direct product_id
  //   final productUuid = remote['product_uuid'] as String?;
  //   if (productUuid == null) return null;

  //   final result = await txn.query(
  //     DbConstants.tableProduct,
  //     columns: [DbConstants.columnId],
  //     where: '${DbConstants.columnUuid} = ?',
  //     whereArgs: [productUuid],
  //   );
  //   return result.isNotEmpty ? result.first[DbConstants.columnId] as int : null;
  // }

  // Future<int?> _resolveCategoryId(
  //   Transaction txn,
  //   Map<String, dynamic> remote,
  // ) async {
  //   final categoryUuid = remote['category_uuid'] as String?;
  //   if (categoryUuid == null) return null;

  //   final result = await txn.query(
  //     DbConstants.tablePriceCategory,
  //     columns: [DbConstants.columnId],
  //     where: '${DbConstants.columnUuid} = ?',
  //     whereArgs: [categoryUuid],
  //   );
  //   return result.isNotEmpty ? result.first[DbConstants.columnId] as int : null;
  // }

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
