// lib/db/db_constants.dart

class DbConstants {
  // Existing constants...
  static const String tableProduct = 'product';
  static const String columnId = '_id';
  static const String columnProductModel = 'model';
  static const String columnProductName = 'name';

  static const String tableInvoiceLine = 'invoice_line';
  static const String columnInvoiceLineInvoiceId = 'invoice_id';
  static const String columnInvoiceLineProductId = 'product_id';
  static const String columnInvoiceLineAmount = 'amount';
  static const String columnInvoiceLinePrice = 'price';

  static const String tableInvoice = 'invoice';
  static const String columnCustomerName = 'customer';
  static const String columnInvoiceDate = 'date';
  static const String columnInvoiceTotal = 'total';
  static const String columnInvoiceCurrency = 'currency';
  static const String columnInvoiceDiscount = 'discount';

  static const String tablePrices = 'prices';
  static const String columnPricesProductId = 'product_id';
  static const String columnPricesPrice = 'price';
  static const String columnPricesPriceCategoryId = 'category_id';

  static const String tablePriceCategory = 'price_category';
  static const String columnPriceCategoryId = '_id';
  static const String columnPriceCategoryName = 'name';
  static const String columnPriceCategoryCurrency = 'currency';

  static const String columnUuid = 'uuid';
  static const String columnUpdatedAt = 'updated_at';

  static const String tableSyncTombstones = 'sync_tombstones';
  static const String tableSyncHistory = 'sync_history';
}
