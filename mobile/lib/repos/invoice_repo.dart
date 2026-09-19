import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/invoice_line.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/order_by.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:sqflite/sqflite.dart';

class InvoiceRepo {
  final Database db;

  const InvoiceRepo(this.db);

  Future<Invoice> insert({
    required String customerName,
    required String currency,
    required DateTime date,
    required double total,
    required List<InvoiceTableRow> lines,
    required double discount,
    int? invoiceId,
    String? orderId,
  }) async {
    int? id = invoiceId;
    return await db.transaction((txn) async {
      if (invoiceId != null) {
        final values =
            await SyncMetadata.withStamp(txn, DbConstants.tableInvoice, {
              DbConstants.columnInvoiceDate: date.toIso8601String(),
              DbConstants.columnCustomerName: customerName,
              DbConstants.columnInvoiceTotal: total,
              DbConstants.columnInvoiceDiscount: discount,
            });
        await txn.update(
          DbConstants.tableInvoice,
          values,
          where: '${DbConstants.columnId} = ?',
          whereArgs: [invoiceId],
        );
        id = invoiceId;
        // Origin is write-once (never in `values` above): re-read so the
        // returned invoice carries the stored one.
        final origin = await txn.query(
          DbConstants.tableInvoice,
          columns: [DbConstants.columnInvoiceOrderId],
          where: '${DbConstants.columnId} = ?',
          whereArgs: [invoiceId],
          limit: 1,
        );
        orderId = origin.firstOrNull?[DbConstants.columnInvoiceOrderId]
            ?.toString();
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tableInvoice,
            rowId: id!,
            op: DbConstants.opUpdate,
          ),
        );
      } else {
        final values = await SyncMetadata.withStamp(
          txn,
          DbConstants.tableInvoice,
          {
            DbConstants.columnInvoiceDate: date.toIso8601String(),
            DbConstants.columnCustomerName: customerName,
            DbConstants.columnInvoiceTotal: total,
            DbConstants.columnInvoiceCurrency: currency,
            DbConstants.columnInvoiceDiscount: discount,
            // Origin is set once at creation and never rewritten above.
            DbConstants.columnInvoiceOrderId: orderId,
          },
        );
        id = await txn.insert(DbConstants.tableInvoice, values);
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tableInvoice,
            rowId: id!,
            op: DbConstants.opInsert,
          ),
        );
      }

      // Match lines by (product, size): update surviving rows in place
      // (stable `_id` keeps `remote_id` matching), soft-delete removed ones,
      // insert genuinely new ones. Never delete-all + reinsert: that churns
      // `_id`s and orphans the server twins.
      final previousLines = await txn.query(
        DbConstants.tableInvoiceLine,
        where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
        whereArgs: [id],
      );
      final previousByLine = <(int, String), Map<String, Object?>>{};
      for (final prev in previousLines) {
        final pid = prev[DbConstants.columnInvoiceLineProductId] as int?;
        if (pid != null) {
          // '' = sizeless (the column is NOT NULL DEFAULT '').
          final size = prev[DbConstants.columnInvoiceLineSize] as String? ?? '';
          previousByLine[(pid, size)] = Map<String, Object?>.from(prev);
        }
      }
      for (var line in lines) {
        final lineValues =
            await SyncMetadata.withStamp(txn, DbConstants.tableInvoiceLine, {
              DbConstants.columnInvoiceLineInvoiceId: id,
              DbConstants.columnInvoiceLineProductId: line.product.id,
              DbConstants.columnInvoiceLineAmount: line.amount,
              DbConstants.columnInvoiceLinePrice: line.unitPrice,
              DbConstants.columnInvoiceLineSize: InvoiceLine.encodeSize(
                line.size,
              ),
            });
        final prev = previousByLine.remove((line.product.id, line.size ?? ''));
        if (prev == null) {
          final lineId = await txn.insert(
            DbConstants.tableInvoiceLine,
            lineValues,
          );
          await SyncMetadata.recordMutation(
            txn,
            ref: MutationRef(
              table: DbConstants.tableInvoiceLine,
              rowId: lineId,
              op: DbConstants.opInsert,
            ),
          );
        } else {
          final prevId = prev[DbConstants.columnId] as int;
          await txn.update(
            DbConstants.tableInvoiceLine,
            lineValues,
            where: '${DbConstants.columnId} = ?',
            whereArgs: [prevId],
          );
          await SyncMetadata.recordMutation(
            txn,
            ref: MutationRef(
              table: DbConstants.tableInvoiceLine,
              rowId: prevId,
              op: DbConstants.opUpdate,
            ),
          );
        }
      }
      for (final removed in previousByLine.values) {
        final removedId = removed[DbConstants.columnId] as int;
        await SyncMetadata.softDelete(
          txn,
          DbConstants.tableInvoiceLine,
          removedId,
        );
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tableInvoiceLine,
            rowId: removedId,
            op: DbConstants.opDelete,
          ),
          payloadOverride: removed,
        );
      }
      return Invoice(
        id: id!,
        customerName: customerName,
        date: date,
        total: total,
        currency: currency,
        lines: lines
            .map(
              (l) => InvoiceLine(
                amount: l.amount,
                price: l.unitPrice.toDouble(),
                invoiceId: id!,
                product: l.product,
                size: l.size,
              ),
            )
            .toList(),
        discount: discount,
        orderId: orderId,
      );
    });
  }

  List<Product> get _products =>
      GetIt.I.get<ProductsController>().products.values.toList();

  Future<List<Invoice>> getInvoices([OrderBy? orderBy]) async {
    final invoiceFilter = await SyncMetadata.notDeletedClause(
      db,
      DbConstants.tableInvoice,
      alias: DbConstants.tableInvoice,
    );
    final lineFilter = await SyncMetadata.notDeletedClause(
      db,
      DbConstants.tableInvoiceLine,
      alias: DbConstants.tableInvoiceLine,
    );
    final result = await db.rawQuery('''
select invoice.*, product_id, amount, price, ${DbConstants.tableInvoiceLine}.${DbConstants.columnInvoiceLineSize} as size from invoice left join invoice_line on invoice._id = invoice_line.invoice_id
and ($lineFilter)
where ($invoiceFilter)
${orderBy != null ? ' ORDER BY ${orderBy.field} ${orderBy.isAscending ? " asc" : " desc"}' : ''}
''');
    return _mergeRows(result);
  }

  /// Single invoice with lines, or null when missing/soft-deleted.
  Future<Invoice?> getInvoiceById(int id) async {
    final invoiceFilter = await SyncMetadata.notDeletedClause(
      db,
      DbConstants.tableInvoice,
      alias: DbConstants.tableInvoice,
    );
    final lineFilter = await SyncMetadata.notDeletedClause(
      db,
      DbConstants.tableInvoiceLine,
      alias: DbConstants.tableInvoiceLine,
    );
    final result = await db.rawQuery(
      '''
select invoice.*, product_id, amount, price, ${DbConstants.tableInvoiceLine}.${DbConstants.columnInvoiceLineSize} as size from invoice left join invoice_line on invoice._id = invoice_line.invoice_id
and ($lineFilter)
where ($invoiceFilter) and invoice.${DbConstants.columnId} = ?
''',
      [id],
    );
    final merged = _mergeRows(result);
    return merged.isEmpty ? null : merged.first;
  }

  List<Invoice> _mergeRows(List<Map<String, Object?>> result) {
    Map<int, Invoice> invoices = {};
    for (var row in result) {
      var invoice = Invoice.fromMap(row);
      if (invoice != null) {
        if (row case {
          'amount': int amount,
          'product_id': int productId,
          'price': double price,
        }) {
          invoice.lines.add(
            InvoiceLine(
              amount: amount,
              price: price,
              invoiceId: invoice.id,
              product: _products.firstWhere(
                (element) => element.id == productId,
              ),
              size: InvoiceLine.decodeSize(row['size']),
            ),
          );
        }
        if (invoices.containsKey(invoice.id)) {
          invoices[invoice.id]?.lines.add(invoice.lines.first);
        } else {
          invoices[invoice.id] = invoice;
        }
      }
    }
    return invoices.values.toList();
  }

  /// Server order uuid → local invoice id for orders that already have an
  /// invoice (for the orders list marker + "go to invoice"). Soft-deleted
  /// invoices don't count; if an order ever links several, the newest wins.
  Future<Map<String, int>> getOrderInvoiceMap() async {
    final filter = await SyncMetadata.notDeletedClause(
      db,
      DbConstants.tableInvoice,
    );
    final rows = await db.query(
      DbConstants.tableInvoice,
      columns: [DbConstants.columnId, DbConstants.columnInvoiceOrderId],
      where: '${DbConstants.columnInvoiceOrderId} IS NOT NULL AND ($filter)',
      orderBy: '${DbConstants.columnId} DESC',
    );
    final map = <String, int>{};
    for (final row in rows) {
      final orderUuid = row[DbConstants.columnInvoiceOrderId]?.toString();
      final id = row[DbConstants.columnId] as int?;
      if (orderUuid != null && orderUuid.isNotEmpty && id != null) {
        map.putIfAbsent(orderUuid, () => id);
      }
    }
    return map;
  }

  /// Server order uuids that already have a local invoice (for the orders
  /// list "invoiced" marker). Soft-deleted invoices don't count.
  Future<Set<String>> getInvoicedOrderIds() async {
    final filter = await SyncMetadata.notDeletedClause(
      db,
      DbConstants.tableInvoice,
    );
    final rows = await db.query(
      DbConstants.tableInvoice,
      columns: [DbConstants.columnInvoiceOrderId],
      where: '${DbConstants.columnInvoiceOrderId} IS NOT NULL AND ($filter)',
    );
    final ids = <String>{};
    for (final row in rows) {
      final id = row[DbConstants.columnInvoiceOrderId]?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  Future<void> delete(Invoice invoice) async {
    await db.transaction((txn) async {
      final lines = await txn.query(
        DbConstants.tableInvoiceLine,
        where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
        whereArgs: [invoice.id],
      );
      final before = await SyncMetadata.softDelete(
        txn,
        DbConstants.tableInvoice,
        invoice.id,
      );
      await SyncMetadata.recordMutation(
        txn,
        ref: MutationRef(
          table: DbConstants.tableInvoice,
          rowId: invoice.id,
          op: DbConstants.opDelete,
        ),
        payloadOverride: before,
      );
      for (final line in lines) {
        final lineId = line[DbConstants.columnId] as int;
        await SyncMetadata.softDelete(
          txn,
          DbConstants.tableInvoiceLine,
          lineId,
        );
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tableInvoiceLine,
            rowId: lineId,
            op: DbConstants.opDelete,
          ),
          payloadOverride: Map<String, Object?>.from(line),
        );
      }
    });
  }
}
