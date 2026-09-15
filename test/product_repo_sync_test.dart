import 'package:flutter_test/flutter_test.dart';
import 'package:i_gen/db.dart';
import 'package:i_gen/models/product.dart';
import 'package:i_gen/repos/product_repo.dart';
import 'package:i_gen/repos/sync_metadata.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_helper.dart';

void main() {
  late Database db;
  late ProductRepo repo;

  setUp(() async {
    db = await openFreshTestDb();
    repo = ProductRepo(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('insert enqueues one insert op with payload', () async {
    final product = await repo.insertProduct(model: 'T1', name: 'Test');

    final ops = await outboxRows(db);
    expect(ops, hasLength(1));
    expect(ops.first[DbConstants.columnTableName], DbConstants.tableProduct);
    expect(ops.first[DbConstants.columnRowId], product.id);
    expect(ops.first[DbConstants.columnOp], DbConstants.opInsert);
    expect(ops.first[DbConstants.columnPayload] as String, contains('T1'));
    expect(ops.first[DbConstants.columnAttempts], 0);
    expect(ops.first[DbConstants.columnLastError], isNull);

    final row = (await db.query(
      DbConstants.tableProduct,
      where: '_id = ?',
      whereArgs: [product.id],
    )).first;
    expect(row[DbConstants.columnUpdatedAt], isNotNull);
  });

  test('update bumps updated_at and enqueues update', () async {
    final product = await repo.insertProduct(model: 'T2', name: 'Before');
    final before = (await db.query(
      DbConstants.tableProduct,
      where: '_id = ?',
      whereArgs: [product.id],
    )).first[DbConstants.columnUpdatedAt];

    await Future<void>.delayed(const Duration(milliseconds: 2));
    expect(await repo.editProduct(product.copyWith(name: 'After')), isTrue);

    final ops = await outboxRows(db);
    expect(ops, hasLength(2));
    expect(ops.last[DbConstants.columnOp], DbConstants.opUpdate);

    final after = (await db.query(
      DbConstants.tableProduct,
      where: '_id = ?',
      whereArgs: [product.id],
    )).first[DbConstants.columnUpdatedAt];
    expect((after as int) >= (before as int), isTrue);
  });

  test('delete soft-deletes, hides row from reads, enqueues delete', () async {
    final product = await repo.insertProduct(model: 'T3', name: 'Gone');

    await repo.deleteProduct(product);

    final raw = await db.query(
      DbConstants.tableProduct,
      where: '_id = ?',
      whereArgs: [product.id],
    );
    expect(raw, hasLength(1));
    expect(raw.first[DbConstants.columnIsDeleted], 1);

    expect(await repo.getProducts(), isEmpty);

    final ops = await outboxRows(db);
    expect(ops, hasLength(2));
    expect(ops.last[DbConstants.columnOp], DbConstants.opDelete);
    expect(ops.last[DbConstants.columnRowId], product.id);
  });

  test('getProducts hides only deleted rows', () async {
    final kept = await repo.insertProduct(model: 'K1', name: 'Kept');
    final gone = await repo.insertProduct(model: 'G1', name: 'Gone');
    await repo.deleteProduct(gone);

    final products = await repo.getProducts();
    expect(products.map((p) => p.id), contains(kept.id));
    expect(products.map((p) => p.id), isNot(contains(gone.id)));
  });

  test(
    're-inserting a soft-deleted product model resurrects the same _id '
    'and preserves remote_id (REPLACE would orphan the server twin)',
    () async {
      final p = await repo.insertProduct(model: 'RC1', name: 'Original');
      // The row has synced: it owns a server twin.
      await db.update(
        DbConstants.tableProduct,
        {DbConstants.columnRemoteId: 'remote-rc1'},
        where: '_id = ?',
        whereArgs: [p.id],
      );
      await repo.deleteProduct(p); // soft-delete: row stays, model stays unique

      // Re-creating the same model must reuse the SAME local row (stable
      // _id), keeping remote_id matched to the server twin — never a REPLACE
      // delete+reinsert, which would mint a new _id and orphan the twin.
      final recreated = await repo.insertProduct(model: 'RC1', name: 'Reborn');
      expect(recreated.id, p.id);
      final row = (await db.query(
        DbConstants.tableProduct,
        where: '_id = ?',
        whereArgs: [p.id],
      )).first;
      expect(row[DbConstants.columnRemoteId], 'remote-rc1');

      final ops = await outboxRows(db);
      expect(ops, hasLength(3)); // insert, delete, update — never re-insert
      final byKind = {
        for (final o in ops) o[DbConstants.columnOp] as String: o,
      };
      expect(
        byKind.keys,
        containsAll([
          DbConstants.opInsert,
          DbConstants.opDelete,
          DbConstants.opUpdate,
        ]),
      );
      expect(byKind[DbConstants.opUpdate]![DbConstants.columnRowId], p.id);
    },
  );

  test('failed transaction enqueues nothing (all or none)', () async {
    await expectLater(
      db.transaction((txn) async {
        await txn.insert(DbConstants.tableProduct, {
          DbConstants.columnProductModel: 'X1',
          DbConstants.columnProductName: 'X',
        });
        await SyncMetadata.recordMutation(
          txn,
          ref: MutationRef(
            table: DbConstants.tableProduct,
            rowId: 999,
            op: DbConstants.opInsert,
          ),
        );
        throw StateError('simulated crash mid-write');
      }),
      throwsStateError,
    );

    expect(await repo.getProducts(), isEmpty);
    expect(await outboxRows(db), isEmpty);
  });

  test('Product model round-trips through repo reads', () async {
    await repo.insertProduct(model: 'M9', name: 'N9');
    final products = await repo.getProducts();
    expect(products, hasLength(1));
    expect(Product.fromMap(products.first.toMap()), isNotNull);
  });
}
