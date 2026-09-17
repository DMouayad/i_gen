// Auth-domain exceptions (Phase 1).
//
// Auth calls must fail fast with a friendly message when offline and must
// never block offline use of the app, so these carry UI-ready messages.

/// Thrown when a sign-in/up/out network call is attempted with no
/// connectivity. Callers should show [message] and let the user continue
/// using the app offline.
class AuthOfflineException implements Exception {
  const AuthOfflineException([
    this.message =
        'No internet connection. You can keep using the app offline and sign in later.',
  ]);

  final String message;

  @override
  String toString() => 'AuthOfflineException: $message';
}

/// Thrown when auth is used but Supabase credentials were not supplied via
/// `--dart-define` (see `SupabaseConfig`). The app stays fully usable.
class AuthNotConfiguredException implements Exception {
  const AuthNotConfiguredException([
    this.message =
        'Sync is not configured on this build. The app works fully offline.',
  ]);

  final String message;

  @override
  String toString() => 'AuthNotConfiguredException: $message';
}

/// A sign-in/up/out attempt reached the server but failed (wrong password,
/// account exists, weak password, …). [message] is safe to show in the UI.
class AuthFailureException implements Exception {
  const AuthFailureException(this.message);

  final String message;

  @override
  String toString() => 'AuthFailureException: $message';
}
