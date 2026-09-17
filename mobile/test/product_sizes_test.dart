import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:i_gen/db.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:i_gen/repos/sync_trigger.dart';
import 'test_helper.dart';

void main() {
  setUp(() {
    SyncTrigger.instance.resetForTests();
  });

  tearDown(() {
    SyncTrigger.instance.resetForTests();
  });

  group('Product sizes model', () {
    test('sortSizes follows kSizeOrder, unknowns last and alphabetical', () {
      expect(
        Product.sortSizes([
          'XL',
          'S',
          'M',
          '3XS',
          '2XL',
          'XS',
          'L',
          '2XS',
          '3XL',
        ]),
        ['3XS', '2XS', 'XS', 'S', 'M', 'L', 'XL', '2XL', '3XL'],
      );
      expect(Product.sortSizes(['ZZ', 'S', 'AA']), ['S', 'AA', 'ZZ']);
      expect(Product.sortSizes([]), isEmpty);
    });

    test('parseSizes reads JSON, lists, and degrades to []', () {
      expect(Product.parseSizes('["M","S"]'), ['S', 'M']);
      expect(Product.parseSizes('[]'), isEmpty);
      expect(Product.parseSizes(['XL', 'S']), ['S', 'XL']);
      expect(Product.parseSizes(null), isEmpty);
      expect(Product.parseSizes('not-json'), isEmpty);
      expect(Product.parseSizes(42), isEmpty);
    });

    test('parseSizeList splits free text and sorts', () {
      expect(Product.parseSizeList('XL, S,M'), ['S', 'M', 'XL']);
      expect(Product.parseSizeList('S M  L'), ['S', 'M', 'L']);
      expect(Product.parseSizeList('  '), isEmpty);
      expect(Product.parseSizeList(''), isEmpty);
    });

    test('hasSizes and singleSize tile policy', () {
      expect(const Product(id: 1, model: 'A', name: 'a').hasSizes, isFalse);
      expect(const Product(id: 1, model: 'A', name: 'a').singleSize, isNull);
      const one = Product(id: 1, model: 'A', name: 'a', sizes: ['M']);
      expect(one.hasSizes, isFalse);
      expect(one.singleSize, 'M');
      const many = Product(id: 1, model: 'A', name: 'a', sizes: ['S', 'M']);
      expect(many.hasSizes, isTrue);
      expect(many.singleSize, isNull);
    });

    test('fromMap defaults missing sizes to [], toMap round-trips', () {
      final noSizes = Product.fromMap({'id': 1, 'model': 'A', 'name': 'a'})!;
      expect(noSizes.sizes, isEmpty);
      const p = Product(id: 1, model: 'A', name: 'a', sizes: ['M', 'S']);
      final back = Product.fromMap(p.toMap())!;
      expect(back.sizes, ['S', 'M']);
      expect(Product.fromMap({'id': 1, 'model': 'A'}), isNull);
    });
  });

  group('Product sizes storage', () {
    test('insert stores sizes sorted; getProducts parses them', () async {
      final db = await openFreshTestDb();
      final repo = ProductRepo(db);
      final created = await repo.insertProduct(
        model: 'SZ',
        name: 'sized',
        sizes: ['XL', 'WEIRD', 'S'],
      );
      expect(created.sizes, ['S', 'XL', 'WEIRD']);

      final fetched = (await repo.getProducts()).firstWhere(
        (p) => p.model == 'SZ',
      );
      expect(fetched.sizes, ['S', 'XL', 'WEIRD']);
      expect(fetched.hasSizes, isTrue);
      await db.close();
    });

    test('update-in-place path and editProduct overwrite sizes', () async {
      final db = await openFreshTestDb();
      final repo = ProductRepo(db);
      final first = await repo.insertProduct(model: 'SZ', name: 'sized');
      expect(first.sizes, isEmpty);

      final second = await repo.insertProduct(
        model: 'SZ',
        name: 'sized',
        sizes: ['M'],
      );
      expect(second.id, first.id);
      expect(second.singleSize, 'M');

      await repo.editProduct(second.copyWith(sizes: ['L', 'S']));
      final fetched = (await repo.getProducts()).firstWhere(
        (p) => p.model == 'SZ',
      );
      expect(fetched.sizes, ['S', 'L']);
      await db.close();
    });

    test(
      'sizeless products round-trip as [] and queue payloads carry sizes',
      () async {
        final db = await openFreshTestDb();
        final repo = ProductRepo(db);
        await repo.insertProduct(model: 'PLAIN', name: 'plain');
        final fetched = (await repo.getProducts()).firstWhere(
          (p) => p.model == 'PLAIN',
        );
        expect(fetched.sizes, isEmpty);

        await repo.insertProduct(model: 'SZ', name: 'sized', sizes: ['M']);
        final ops = await outboxRows(db);
        final payloads = [
          for (final o in ops)
            jsonDecode(o[DbConstants.columnPayload] as String)
                as Map<String, dynamic>,
        ];
        final sized = payloads.firstWhere((p) => p['model'] == 'SZ');
        expect(sized['sizes'], '["M"]');
        await db.close();
      },
    );

    test('v1 -> v3 upgrade backfills sizeless [] on existing rows', () async {
      final v1 = await openV1Fixture();
      final path = v1.path;
      await v1.close();

      final db = await reopenViaProvider(path);
      final rows = await db.query(DbConstants.tableProduct);
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row[DbConstants.columnProductSizes], '[]');
      }
      // Repo reads work on the upgraded rows.
      final products = await ProductRepo(db).getProducts();
      expect(products, isNotEmpty);
      expect(products.every((p) => p.sizes.isEmpty), isTrue);
      await db.close();
    });
  });
}
