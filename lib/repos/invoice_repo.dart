import 'package:get_it/get_it.dart';
import 'package:i_gen/controllers/products_controller.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/models/invoice.dart';
import 'package:i_gen/models/invoice_line.dart';
import 'package:i_gen/models/invoice_table_row.dart';
import 'package:i_gen/models/order_by.dart';
import 'package:i_gen/models/product.dart';
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
  }) async {
    int? id = invoiceId;
    return await db.transaction((txn) async {
      if (invoiceId != null) {
        await txn.update(
          DbConstants.tableInvoice,
          {
            DbConstants.columnInvoiceDate: date.toIso8601String(),
            DbConstants.columnCustomerName: customerName,
            DbConstants.columnInvoiceTotal: total,
            DbConstants.columnInvoiceDiscount: discount,
          },
          where: '${DbConstants.columnId} = ?',
          whereArgs: [invoiceId],
        );
      } else {
        id = await txn.insert(DbConstants.tableInvoice, {
          DbConstants.columnInvoiceDate: date.toIso8601String(),
          DbConstants.columnCustomerName: customerName,
          DbConstants.columnInvoiceTotal: total,
          DbConstants.columnInvoiceCurrency: currency,
          DbConstants.columnInvoiceDiscount: discount,
        });
      }
      await txn.delete(
        DbConstants.tableInvoiceLine,
        where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
        whereArgs: [id],
      );

      for (var line in lines) {
        await txn.insert(DbConstants.tableInvoiceLine, {
          DbConstants.columnInvoiceLineInvoiceId: id,
          DbConstants.columnInvoiceLineProductId: line.product.id,
          DbConstants.columnInvoiceLineAmount: line.amount,
          DbConstants.columnInvoiceLinePrice: line.unitPrice,
        });
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
              ),
            )
            .toList(),
        discount: discount,
      );
    });
  }

  List<Product> get _products =>
      GetIt.I.get<ProductsController>().products.values.toList();

  Future<List<Invoice>> getInvoices([OrderBy? orderBy]) async {
    final result = await db.rawQuery('''
select invoice.*, product_id, amount,price from invoice left join invoice_line on invoice._id = invoice_line.invoice_id
${orderBy != null ? ' ORDER BY ${orderBy.field} ${orderBy.isAscending ? " asc" : " desc"}' : ''}
''');
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

  Future<void> delete(Invoice invoice) async {
    await db.delete(
      DbConstants.tableInvoice,
      where: '${DbConstants.columnId} = ?',
      whereArgs: [invoice.id],
    );
    await db.delete(
      DbConstants.tableInvoiceLine,
      where: '${DbConstants.columnInvoiceLineInvoiceId} = ?',
      whereArgs: [invoice.id],
    );
  }
}
