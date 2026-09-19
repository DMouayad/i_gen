/// Remote-access boundary for the sync engine.
///
/// The engine never talks to Supabase directly; it talks to a
/// [RemoteGateway]. Tests inject a fake; the wiring agent injects a
/// `supabase_flutter`-backed adapter once that package lands in pubspec
/// (another agent owns it — this module deliberately imports no third-party
/// network packages so `flutter analyze` stays green until then).
library;

import 'package:i_gen/db.dart';

/// Local → remote table mapping (Phase 0 names mirror local column names).
class SyncTables {
  static const Map<String, String> localToRemote = {
    DbConstants.tableProduct: 'products',
    DbConstants.tableInvoice: 'invoices',
    DbConstants.tableInvoiceLine: 'invoice_lines',
    DbConstants.tablePriceCategory: 'price_categories',
    DbConstants.tablePrices: 'prices',
  };

  /// Parents before children so `remote_id` matching can resolve foreign
  /// keys at merge time (spec: cross-table order is resolved by matching,
  /// not by global queue ordering).
  static const List<String> orderedLocalTables = [
    DbConstants.tableProduct,
    DbConstants.tablePriceCategory,
    DbConstants.tableInvoice,
    DbConstants.tablePrices,
    DbConstants.tableInvoiceLine,
  ];

  static String remoteFor(String localTable) => localToRemote[localTable]!;

  static String? localFor(String remoteTable) {
    for (final entry in localToRemote.entries) {
      if (entry.value == remoteTable) return entry.key;
    }
    return null;
  }
}

/// Result of one server upsert: the canonical server id plus the
/// server-owned timestamp. The engine writes both back locally so the next
/// pull does not see the just-pushed row as "remote newer" (pull churn).
class RemoteUpsertResult {
  const RemoteUpsertResult({required this.id, required this.updatedAtMillis});

  final String id;
  final int updatedAtMillis;
}

/// Remote row field conventions (both the Supabase adapter and fakes):
/// - `id`: server uuid string.
/// - `owner_id`: Supabase user id string.
/// - `updated_at`: millis-since-epoch int (or ISO-8601 string; normalized).
/// - `is_deleted`: 0/1 int or bool (normalized).
/// - all other keys mirror the local SQLite column names (Phase 0).
abstract class RemoteGateway {
  /// Insert (when [remoteId] is null) or update one row. Returns the server
  /// id and server timestamp.
  ///
  /// [opId] is the client-generated idempotency key: repeat delivery of the
  /// same [opId] must not create a duplicate server row, so a crash between
  /// server-ack and local op-delete replays safely.
  Future<RemoteUpsertResult> upsertRow({
    required String remoteTable,
    required Map<String, dynamic> row,
    required String? remoteId,
    required String ownerId,
    required String opId,
  });

  /// Server-side soft-delete (sets `is_deleted`). Returns the server id and
  /// timestamp. Same [opId] idempotency contract as [upsertRow].
  Future<RemoteUpsertResult> deleteRow({
    required String remoteTable,
    required String remoteId,
    required String ownerId,
    required String opId,
  });

  /// Company-visible server rows with `updated_at > [lastPullAtMillis]`
  /// (null = full pull). Ordered ascending by `updated_at` when possible.
  /// RLS is the visibility lock (staff share the catalog, customers get
  /// none of it); the gateway must NOT narrow to one owner, or multi-user
  /// devices starve. [ownerId] gates login, audit only beyond that.
  Future<List<Map<String, dynamic>>> pullTable({
    required String remoteTable,
    required String ownerId,
    required int? lastPullAtMillis,
  });
}
