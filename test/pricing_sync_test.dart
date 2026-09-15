import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/models/price_category.dart';
import 'package:i_gen/repos/pricing_category_repo.dart';
import 'package:i_gen/repos/product_pricing_repo.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helper.dart';

void main() {
  late Database db;
  late PricingCategoryRepo categories;
  late ProductPricingRepo pricing;
  late ProductRepo products;

  setUp(() async {
    db = await openFreshTestDb();
    categories = PricingCategoryRepo(db);
    pricing = ProductPricingRepo(db);
    products = ProductRepo(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('category insert/save/delete enqueue matching ops', () async {
    final id = await categories.insert(
      PriceCategory(id: 0, name: 'Retail', currency: 'USD'),
    );
    var ops = await outboxRows(db);
    expect(ops, hasLength(1));
    expect(ops.first[DbConstants.columnOp], DbConstants.opInsert);
    expect(
      ops.first[DbConstants.columnTableName],
      DbConstants.tablePriceCategory,
    );

    // save() on the same name keeps the row id and enqueues update.
    final sameId = await categories.save(name: 'Retail', currency: 'EUR');
    expect(sameId, id);
    ops = await outboxRows(db);
    expect(ops, hasLength(2));
    expect(ops.last[DbConstants.columnOp], DbConstants.opUpdate);
    expect(ops.last[DbConstants.columnRowId], id);

    await categories.delete(id);
    ops = await outboxRows(db);
    expect(ops, hasLength(3));
    expect(ops.last[DbConstants.columnOp], DbConstants.opDelete);

    expect(await categories.getAll(), isEmpty);
    final raw = await db.query(
      DbConstants.tablePriceCategory,
      where: '_id = ?',
      whereArgs: [id],
    );
    expect(raw.first[DbConstants.columnIsDeleted], 1);
  });

  test('pricing save inserts then updates without duplicating', () async {
    final product = await products.insertProduct(model: 'PR1', name: 'pr');
    final catId = await categories.insert(
      PriceCategory(id: 0, name: 'Wholesale', currency: 'USD'),
    );
    final before = (await outboxRows(db)).length;

    await pricing.save(
      priceCategoryId: catId,
      productId: product.id,
      price: 42.5,
      currency: 'USD',
    );
    await pricing.save(
      priceCategoryId: catId,
      productId: product.id,
      price: 44.0,
      currency: 'USD',
    );

    final rows = await db.query(DbConstants.tablePrices);
    expect(rows, hasLength(1));
    expect(rows.first[DbConstants.columnPricesPrice], 44.0);

    final ops = (await outboxRows(db)).skip(before).toList();
    final priceOps = ops
        .where((o) => o[DbConstants.columnTableName] == DbConstants.tablePrices)
        .toList();
    expect(priceOps, hasLength(2));
    expect(priceOps.first[DbConstants.columnOp], DbConstants.opInsert);
    expect(priceOps.last[DbConstants.columnOp], DbConstants.opUpdate);
    expect(
      priceOps.first[DbConstants.columnRowId],
      priceOps.last[DbConstants.columnRowId],
    );

    final matrix = await pricing.getProductsPricing();
    expect(matrix['PR1']?['Wholesale']?.price, 44.0);
  });

  test('reads hide soft-deleted pricing rows', () async {
    final product = await products.insertProduct(model: 'PR2', name: 'pr2');
    final catId = await categories.insert(
      PriceCategory(id: 0, name: 'VIP', currency: 'USD'),
    );
    await pricing.save(
      priceCategoryId: catId,
      productId: product.id,
      price: 10,
      currency: 'USD',
    );
    expect((await pricing.getProductsPricing())['PR2'], isNotEmpty);

    await categories.delete(catId);
    final matrix = await pricing.getProductsPricing();
    // Category gone -> no priced entry for the model.
    expect(matrix['PR2']?.isEmpty ?? true, isTrue);
  });
}
