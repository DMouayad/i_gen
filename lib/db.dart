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
  foreign key(${DbConstants.columnInvoiceLineProductId}) references ${DbConstants.tableProduct}(${DbConstants.columnId})
  unique(${DbConstants.columnInvoiceLineInvoiceId}, ${DbConstants.columnInvoiceLineProductId}) ON CONFLICT REPLACE

  )
''');

        await db.execute('''
create table ${DbConstants.tableInvoiceLines} (
  ${DbConstants.columnInvoiceLineInvoiceId} integer not null,
  ${DbConstants.columnInvoiceLineProductId} integer not null,
  foreign key(${DbConstants.columnInvoiceLineInvoiceId}) references ${DbConstants.tableInvoice}(${DbConstants.columnId}),
  foreign key(${DbConstants.columnInvoiceLineProductId}) references ${DbConstants.tableProduct}(${DbConstants.columnId})
  )
 ''');

        await db.execute('''
create table ${DbConstants.tablePrices} (
  ${DbConstants.columnId} integer primary key autoincrement,
  ${DbConstants.columnPricesProductId} integer not null,
  ${DbConstants.columnPricesPrice} REAL not null,
  ${DbConstants.columnPricesPriceCategoryId} integer not null,
  foreign key(${DbConstants.columnPricesProductId}) references ${DbConstants.tableProduct}(${DbConstants.columnId}),
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
        .then((value) => value.first.values.first);
    if (storedProductsCount == 0) {
      await db.rawInsert('''
INSERT INTO "product" VALUES (1,'A1','مشد صدر');
INSERT INTO "product" VALUES (2,'A1+','مشد صدر عريض');
INSERT INTO "product" VALUES (3,'B1','مشد حزام بطن');
INSERT INTO "product" VALUES (4,'D1','سليب بطن');
INSERT INTO "product" VALUES (5,'D2','سليب بطن ظهر عالي');
INSERT INTO "product" VALUES (6,'C1','شورت فوق الركبة');
INSERT INTO "product" VALUES (8,'C2','شورت تحت الركبة');
INSERT INTO "product" VALUES (9,'A2','مشد بودي صدر مع بطن');
INSERT INTO "product" VALUES (10,'A3','مشد بودي مع أكمام');
INSERT INTO "product" VALUES (11,'H1','مشد ذراعين');
INSERT INTO "product" VALUES (12,'H2','مشد ذراعين عريض');
INSERT INTO "product" VALUES (13,'K1','شورت فوق الركبة مع خلفية تول');
INSERT INTO "product" VALUES (14,'K2','شورت تحت الركبة مع خلفية تول');
INSERT INTO "product" VALUES (15,'K3','أفارول فوق الركبة مع خلفية تول');
INSERT INTO "product" VALUES (16,'K4','أفارول للكاحل مع خلفية تول');
INSERT INTO "product" VALUES (17,'K5','أفارول كامل مع يدين مع خلفية تول');
INSERT INTO "product" VALUES (18,'E1','مشد تثدي رجالي');
INSERT INTO "product" VALUES (19,'E2','كنزة حفر رجالي');
INSERT INTO "product" VALUES (20,'E3','أفارول رجالي فوق الركبة');
INSERT INTO "product" VALUES (21,'G1','أفارول نسائي فوق الركبة');
INSERT INTO "product" VALUES (22,'G2','أفارول نسائي للكاحل');
INSERT INTO "product" VALUES (23,'M1','مشد فخذين');
INSERT INTO "product" VALUES (24,'C3','مشد طويل للكاحل');
INSERT INTO "product" VALUES (25,'S1','مشد عنق');
INSERT INTO "product" VALUES (26,'S2','مشد وجه');
''');
    }
  }
}
