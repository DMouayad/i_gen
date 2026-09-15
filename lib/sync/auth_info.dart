import 'dart:async';

/// Identity contract for the sync engine (Phase 1 auth boundary).
///
/// `lib/auth/` is being built in parallel and does not exist yet. Per
/// `specs/phase-1-auth.md`, auth owns a locally cached `owner_id` (the
/// Supabase user id) that the sync engine stamps on every upload to satisfy
/// the RLS `WITH CHECK (owner_id = auth.uid())` from Phase 0.
///
/// When `lib/auth/` lands, the wiring agent should adapt its session holder
/// to [AuthInfoProvider] (a trivial wrapper around the cached owner id and
/// its auth-state stream) and inject it into the sync engine. Until then —
/// and in tests — use [InMemoryAuthInfoProvider].
abstract class AuthInfoProvider {
  /// Cached Supabase user id, or null when logged out. Sync activates only
  /// while this is non-null; the app stays fully usable offline otherwise.
  String? get ownerId;

  /// Emits the current [ownerId] whenever sign-in/out changes it.
  Stream<String?> get ownerIdStream;
}

/// Test / placeholder [AuthInfoProvider] with a manually set owner id.
class InMemoryAuthInfoProvider implements AuthInfoProvider {
  InMemoryAuthInfoProvider([String? ownerId]) : _ownerId = ownerId;

  String? _ownerId;
  final StreamController<String?> _controller =
      StreamController<String?>.broadcast();

  /// Simulate sign-in / sign-out in tests or before `lib/auth/` exists.
  void setOwnerId(String? ownerId) {
    _ownerId = ownerId;
    if (!_controller.isClosed) {
      _controller.add(ownerId);
    }
  }

  @override
  String? get ownerId => _ownerId;

  @override
  Stream<String?> get ownerIdStream => _controller.stream;

  Future<void> dispose() => _controller.close();
}
