import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db/db_constants.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/invoice_line.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/order_by.dart';
import 'package:i_gen/models/product.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

class InvoiceRepo {
  final Database db;

  const InvoiceRepo(this.db);

  List<Product> get _products =>
      GetIt.I.get<ProductsController>().products.values.toList();

  /// Insert new or update existing invoice
  Future<Invoice> insert({
    required String customerName,
    required String currency,
    required DateTime date,
    required double total,
    required List<InvoiceTableRow> lines,
    required double discount,
    int? invoiceId,
    String? existingUuid,
  }) async {
    int? id = invoiceId;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final invoiceUuid = existingUuid ?? const Uuid().v4();

    return await db.transaction((txn) async {
      if (invoiceId != null) {
        // Update existing
        await txn.update(
          DbConstants.tableInvoice,
          {
            DbConstants.columnInvoiceDate: date.toIso8601String(),
            DbConstants.columnCustomerName: customerName,
            DbConstants.columnInvoiceTotal: total,
            DbConstants.columnInvoiceDiscount: discount,
            DbConstants.columnUpdatedAt: now,
          },
          where: '${DbConstants.columnId} = ?',
          whereArgs: [invoiceId],
        );
      } else {
        // Insert new
        id = await txn.insert(DbConstants.tableInvoice, {
          DbConstants.columnInvoiceDate: date.toIso8601String(),
          DbConstants.columnCustomerName: customerName,
          DbConstants.columnInvoiceTotal: total,
          DbConstants.columnInvoiceCurrency: currency,
          DbConstants.columnInvoiceDiscount: discount,
          DbConstants.columnUuid: invoiceUuid,
          DbConstants.columnUpdatedAt: now,
        });
      }

      // Remove old lines
      await txn.delete(
        DbConstants.tableInvoiceLine,
        where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
        whereArgs: [id],
      );

      // Insert new lines
      for (var line in lines) {
        await txn.insert(DbConstants.tableInvoiceLine, {
          DbConstants.columnInvoiceLineInvoiceId: id,
          DbConstants.columnInvoiceLineProductId: line.product.id,
          DbConstants.columnInvoiceLineAmount: line.amount,
          DbConstants.columnInvoiceLinePrice: line.unitPrice,
          DbConstants.columnUuid: const Uuid().v4(),
          DbConstants.columnUpdatedAt: now,
        });
      }

      return Invoice(
        id: id!,
        customerName: customerName,
        date: date,
        total: total,
        currency: currency,
        discount: discount,
        uuid: invoiceUuid,
        updatedAt: now,
        lines: lines
            .map(
              (l) => InvoiceLine(
                amount: l.amount,
                price: l.unitPrice.toDouble(),
                invoiceId: id!,
                product: l.product,
              ),
            )
            .toList(),
      );
    });
  }

  Future<List<Invoice>> getInvoices([OrderBy? orderBy]) async {
    final result = await db.rawQuery('''
    SELECT invoice.*, product_id, amount, price 
    FROM ${DbConstants.tableInvoice} invoice 
    LEFT JOIN ${DbConstants.tableInvoiceLine} 
      ON invoice.${DbConstants.columnId} = ${DbConstants.tableInvoiceLine}.${DbConstants.columnInvoiceLineInvoiceId}
    ${orderBy != null ? 'ORDER BY ${orderBy.field} ${orderBy.isAscending ? "ASC" : "DESC"}' : ''}
  ''');

    // Group rows by invoice ID
    final Map<int, List<Map<String, dynamic>>> grouped = {};

    for (final row in result) {
      final id = row['_id'] as int;
      grouped.putIfAbsent(id, () => []).add(row);
    }

    // Build invoices with their lines
    final invoices = <Invoice>[];

    for (final entry in grouped.entries) {
      final rows = entry.value;
      final firstRow = rows.first;

      // Parse invoice from first row
      final invoice = Invoice.fromMap(firstRow);

      // Parse all lines
      final lines = <InvoiceLine>[];
      for (final row in rows) {
        if (row['product_id'] != null) {
          final productId = row['product_id'] as int;
          final product = _products.firstWhere(
            (p) => p.id == productId,
            orElse: () => Product(id: productId, model: '', name: 'Unknown'),
          );

          lines.add(
            InvoiceLine(
              amount: row['amount'] as int,
              price: (row['price'] as num).toDouble(),
              invoiceId: invoice.id,
              product: product,
            ),
          );
        }
      }

      // Create invoice with lines using copyWith
      invoices.add(invoice.copyWith(lines: lines));
    }

    return invoices;
  }

  /// Get all invoices (excludes deleted via tombstones)
  // Future<List<Invoice>> getInvoices([OrderBy? orderBy]) async {
  //   final result = await db.rawQuery('''
  //     SELECT invoice.*, product_id, amount, price
  //     FROM ${DbConstants.tableInvoice} invoice
  //     LEFT JOIN ${DbConstants.tableInvoiceLine}
  //       ON invoice.${DbConstants.columnId} = ${DbConstants.tableInvoiceLine}.${DbConstants.columnInvoiceLineInvoiceId}
  //     ${orderBy != null ? 'ORDER BY ${orderBy.field} ${orderBy.isAscending ? "ASC" : "DESC"}' : ''}
  //   ''');

  //   Map<int, Invoice> invoices = {};
  //   for (var row in result) {
  //     var invoice = Invoice.fromMap(row);
  //     if (invoice != null) {
  //       if (row case {
  //         'amount': int amount,
  //         'product_id': int productId,
  //         'price': double price,
  //       }) {
  //         final product = _products.firstWhere(
  //           (p) => p.id == productId,
  //           orElse: () => Product(id: productId, model: '', name: 'Unknown'),
  //         );
  //         invoice.lines.add(
  //           InvoiceLine(
  //             amount: amount,
  //             price: price,
  //             invoiceId: invoice.id,
  //             product: product,
  //           ),
  //         );
  //       }
  //       if (invoices.containsKey(invoice.id)) {
  //         invoices[invoice.id]?.lines.add(invoice.lines.first);
  //       } else {
  //         invoices[invoice.id] = invoice;
  //       }
  //     }
  //   }
  //   return invoices.values.toList();
  // }

  /// Delete invoice and record tombstones for sync
  Future<void> delete(Invoice invoice) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Record tombstone for invoice
      if (invoice.uuid.isNotEmpty) {
        await txn.insert(
          DbConstants.tableSyncTombstones,
          {
            'table_name': DbConstants.tableInvoice,
            'uuid': invoice.uuid,
            'deleted_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Record tombstones for lines
      final lines = await txn.query(
        DbConstants.tableInvoiceLine,
        columns: [DbConstants.columnUuid],
        where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
        whereArgs: [invoice.id],
      );

      for (final line in lines) {
        final uuid = line[DbConstants.columnUuid] as String?;
        if (uuid != null && uuid.isNotEmpty) {
          await txn.insert(
            DbConstants.tableSyncTombstones,
            {
              'table_name': DbConstants.tableInvoiceLine,
              'uuid': uuid,
              'deleted_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // Hard delete
      await txn.delete(
        DbConstants.tableInvoiceLine,
        where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
        whereArgs: [invoice.id],
      );
      await txn.delete(
        DbConstants.tableInvoice,
        where: '${DbConstants.columnId} = ?',
        whereArgs: [invoice.id],
      );
    });
  }

  /// Get invoice by UUID (for sync lookups)
  Future<Invoice?> getByUuid(String uuid) async {
    final result = await db.query(
      DbConstants.tableInvoice,
      where: '${DbConstants.columnUuid} = ?',
      whereArgs: [uuid],
    );
    if (result.isEmpty) return null;
    return Invoice.fromMap(result.first);
  }
}
