import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_gateway.dart';

/// `supabase_flutter`-backed [RemoteGateway] (fills the Spec-axis gap: the
/// engine previously had only a test fake).
///
/// Upload idempotency is real, not notional: every upload carries the
/// client's `op_id` as `client_op_id` (UNIQUE server-side, see
/// `supabase/phase-0-schema.sql`), so a crash between server-ack and local
/// op-delete replays as an upsert that matches the same row instead of a
/// duplicate insert.
class SupabaseGateway implements RemoteGateway {
  SupabaseGateway(this._client);

  final SupabaseClient _client;

  static String _asIso(int millis) => DateTime.fromMillisecondsSinceEpoch(
    millis,
    isUtc: true,
  ).toIso8601String();

  static int _asMillis(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final asInt = int.tryParse(value);
      if (asInt != null) return asInt;
      return DateTime.parse(value).toUtc().millisecondsSinceEpoch;
    }
    throw ArgumentError('Cannot interpret $value as a timestamp');
  }

  @override
  Future<RemoteUpsertResult> upsertRow({
    required String remoteTable,
    required Map<String, dynamic> row,
    required String? remoteId,
    required String ownerId,
    required String opId,
  }) async {
    final payload = <String, dynamic>{
      ...row,
      'owner_id': ownerId,
      'client_op_id': opId,
    };
    final Map<String, dynamic> saved;
    if (remoteId == null) {
      // Insert-or-replay: onConflict matches a previous crashed attempt.
      saved = await _client
          .from(remoteTable)
          .upsert(payload, onConflict: 'client_op_id')
          .select('id,updated_at')
          .single();
    } else {
      // Update path: identity columns are server-owned after insert.
      // client_op_id already matched the row; owner_id must never move
      // (an admin edit would otherwise steal row ownership).
      payload.remove('client_op_id');
      payload.remove('owner_id');
      saved = await _client
          .from(remoteTable)
          .update(payload)
          .eq('id', remoteId)
          .select('id,updated_at')
          .single();
    }
    return RemoteUpsertResult(
      id: saved['id'] as String,
      updatedAtMillis: _asMillis(saved['updated_at']),
    );
  }

  @override
  Future<RemoteUpsertResult> deleteRow({
    required String remoteTable,
    required String remoteId,
    required String ownerId,
    required String opId,
  }) async {
    // Server-side tombstone (not a hard delete): other devices pull it.
    final saved = await _client
        .from(remoteTable)
        .update({'is_deleted': true})
        .eq('id', remoteId)
        .select('id,updated_at')
        .single();
    return RemoteUpsertResult(
      id: saved['id'] as String,
      updatedAtMillis: _asMillis(saved['updated_at']),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> pullTable({
    required String remoteTable,
    required String ownerId,
    required int? lastPullAtMillis,
  }) async {
    // Company-visible reads: the RLS policies are the lock (staff share all
    // business rows, distributors see none of the catalog), so the client
    // must NOT narrow to owner_id — that filter hid other users' catalog
    // rows and starved multi-user devices. [ownerId] is still required
    // (login-gated reads) but only audit from here on.
    var query = _client.from(remoteTable).select();
    if (lastPullAtMillis != null) {
      query = query.gt('updated_at', _asIso(lastPullAtMillis));
    }
    final rows = await query.order('updated_at', ascending: true);
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }
}
