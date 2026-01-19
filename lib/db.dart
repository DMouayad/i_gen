import 'package:sqflite/sqflite.dart';

class DbConstants {
  static const String tableProduct = 'product';
  static const String columnId = '_id';
  static const String columnProductModel = 'model';
  static const String columnProductName = 'name';

  //
  static const String tableInvoiceLine = 'invoice_line';
  static const String columnInvoiceLineInvoiceId = 'invoice_id';
  static const String columnInvoiceLineProductId = 'product_id';
  static const String columnInvoiceLineAmount = 'amount';
  static const String columnInvoiceLinePrice = 'price';

  //
  static const String tableInvoice = 'invoice';
  static const String columnCustomerName = 'customer';
  static const String columnInvoiceDate = 'date';
  static const String columnInvoiceTotal = 'total';
  static const String columnInvoiceCurrency = 'currency';
  static const String columnInvoiceDiscount = 'discount';

  //
  static const String tableInvoiceLines = 'invoice_lines';
  //
  static const String tablePrices = 'prices';
  static const String columnPricesProductId = 'product_id';
  static const String columnPricesPrice = 'price';
  static const String columnPricesPriceCategoryId = 'category_id';

  //
  static const String tablePriceCategory = 'price_category';
  static const String columnPriceCategoryId = '_id';
  static const String columnPriceCategoryName = 'name';
  static const String columnPriceCategoryCurrency = 'currency';
}

class DbProvider {
  static Future<Database> open(String path) async {
    return await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table ${DbConstants.tableProduct} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnProductModel} text not null unique,
  ${DbConstants.columnProductName} text not null)
''');
        await db.execute('''
create table ${DbConstants.tableInvoice} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnInvoiceTotal} REAL not null,
  ${DbConstants.columnCustomerName} text not null,
  ${DbConstants.columnInvoiceDate} text not null,
  ${DbConstants.columnInvoiceCurrency} text not null,
  ${DbConstants.columnInvoiceDiscount} REAL not null
  )
''');
        await db.execute('''
create INDEX "customer_name" on ${DbConstants.tableInvoice} ( ${DbConstants.columnCustomerName} )
 ''');
        await db.execute('''
create table ${DbConstants.tableInvoiceLine} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnInvoiceLineInvoiceId} integer not null,
  ${DbConstants.columnInvoiceLineProductId} integer not null,
  ${DbConstants.columnInvoiceLineAmount} integer not null,
  ${DbConstants.columnInvoiceLinePrice} REAL not null,
  foreign key(${DbConstants.columnInvoiceLineInvoiceId}) references ${DbConstants.tableInvoice}(${DbConstants.columnId}),
  foreign key(${DbConstants.columnInvoiceLineProductId}) references ${DbConstants.tableProduct}(${DbConstants.columnId}) ON DELETE RESTRICT
  unique(${DbConstants.columnInvoiceLineInvoiceId}, ${DbConstants.columnInvoiceLineProductId}) ON CONFLICT REPLACE

  )
''');

        await db.execute('''
create table ${DbConstants.tablePrices} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnPricesProductId} integer not null,
  ${DbConstants.columnPricesPrice} REAL not null,
  ${DbConstants.columnPricesPriceCategoryId} integer not null,
  foreign key(${DbConstants.columnPricesProductId}) references ${DbConstants.tableProduct}(${DbConstants.columnId}) ON DELETE CASCADE,
  foreign key(${DbConstants.columnPricesPriceCategoryId}) references ${DbConstants.tablePriceCategory}(${DbConstants.columnId})
  unique(${DbConstants.columnPricesProductId}, ${DbConstants.columnPricesPriceCategoryId}) ON CONFLICT REPLACE
  )
''');
        await db.execute('''
create table ${DbConstants.tablePriceCategory} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnPriceCategoryName} text not null unique,
  ${DbConstants.columnPriceCategoryCurrency} text not null
  )
''');
      },
    );
  }
}

class DbSeeder {
  static Future<void> seedProducts(Database db) async {
    final storedProductsCount = await db
        .rawQuery('''select count (*) from ${DbConstants.tableProduct}''')
        .then((value) => value.first.values.first as int);
    if (storedProductsCount == 0) {
      final products = [
        {'_id': 1, 'model': 'A1', 'name': 'مشد صدر'},
        {'_id': 2, 'model': 'A1+', 'name': 'مشد صدر عريض'},
        {'_id': 3, 'model': 'B1', 'name': 'مشد حزام بطن'},
        {'_id': 4, 'model': 'D1', 'name': 'سليب بطن'},
        {'_id': 5, 'model': 'D2', 'name': 'سليب بطن ظهر عالي'},
        {'_id': 6, 'model': 'C1', 'name': 'شورت فوق الركبة'},
        {'_id': 8, 'model': 'C2', 'name': 'شورت تحت الركبة'},
        {'_id': 9, 'model': 'A2', 'name': 'مشد بودي صدر مع بطن'},
        {'_id': 10, 'model': 'A3', 'name': 'مشد بودي مع أكمام'},
        {'_id': 11, 'model': 'H1', 'name': 'مشد ذراعين'},
        {'_id': 12, 'model': 'H2', 'name': 'مشد ذراعين عريض'},
        {'_id': 13, 'model': 'K1', 'name': 'شورت فوق الركبة مع خلفية تول'},
        {'_id': 14, 'model': 'K2', 'name': 'شورت تحت الركبة مع خلفية تول'},
        {'_id': 15, 'model': 'K3', 'name': 'أفارول فوق الركبة مع خلفية تول'},
        {'_id': 16, 'model': 'K4', 'name': 'أفارول للكاحل مع خلفية تول'},
        {'_id': 17, 'model': 'K5', 'name': 'أفارول كامل مع يدين مع خلفية تول'},
        {'_id': 18, 'model': 'E1', 'name': 'مشد تثدي رجالي'},
        {'_id': 19, 'model': 'E2', 'name': 'كنزة حفر رجالي'},
        {'_id': 20, 'model': 'E3', 'name': 'أفارول رجالي فوق الركبة'},
        {'_id': 21, 'model': 'G1', 'name': 'أفارول نسائي فوق الركبة'},
        {'_id': 22, 'model': 'G2', 'name': 'أفارول نسائي للكاحل'},
        {'_id': 23, 'model': 'M1', 'name': 'مشد فخذين'},
        {'_id': 24, 'model': 'C3', 'name': 'مشد طويل للكاحل'},
        {'_id': 25, 'model': 'S1', 'name': 'مشد عنق'},
        {'_id': 26, 'model': 'S2', 'name': 'مشد وجه'},
      ];

      final batch = db.batch();
      for (final product in products) {
        batch.insert(DbConstants.tableProduct, product);
      }
      await batch.commit(noResult: true);
    }
  }
}
