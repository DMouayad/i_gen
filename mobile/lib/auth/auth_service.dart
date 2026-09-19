import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:i_gen/auth/auth_exceptions.dart';
import 'package:i_gen/auth/supabase_config.dart';

/// Closed role set (Phase 6): single company, admin-invited only.
/// The authoritative role lives in `public.profiles`; a copy is mirrored
/// into the auth token metadata so RLS can read it without joins.
enum UserRole {
  admin,
  employee,
  customer;

  /// Parses the token-metadata copy; unknown/missing ⇒ null (treated as
  /// signed-in with no privileges until profiles refresh).
  static UserRole? tryParse(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'admin':
        return UserRole.admin;
      case 'employee':
        return UserRole.employee;
      case 'customer':
        return UserRole.customer;
      default:
        return null;
    }
  }
}

/// Email/password authentication via Supabase Auth (Phase 1).
///
/// - Session is persisted by `supabase_flutter` and restored on startup, so
///   sign-in survives restarts without any network on the next launch.
/// - [cachedOwnerId] is the Supabase user id, additionally mirrored to local
///   storage at login so the Phase 3 sync engine can stamp it on every upload
///   (satisfying the Phase 0 RLS `WITH CHECK (owner_id = auth.uid())`).
/// - [signOut] clears the remote session and the cached owner id but never
///   touches local business tables — logout is safe on a shared device.
/// - Auth calls fail fast with [AuthOfflineException] when offline; no auth
///   state is ever required to use the app.
///
/// Obtain via [instance] (registered by [initialize] at startup).
class AuthService {
  AuthService._();

  /// Singleton used by the UI and (later) the sync engine.
  static final AuthService instance = AuthService._();

  /// SharedPreferences key for the locally cached owner id.
  @visibleForTesting
  static const String ownerIdPrefsKey = 'sync_owner_id';

  /// Initializes the Supabase client once at startup and restores the
  /// persisted session. Never throws and never blocks: when unconfigured or
  /// offline the app simply starts signed out.
  static Future<void> initialize() async {
    if (!SupabaseConfig.isConfigured) {
      debugPrint(
        'AuthService: SUPABASE_URL/ANON_KEY missing — running offline-only.',
      );
      return;
    }
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
      await instance.restoreSession();
    } catch (e) {
      // Startup must never fail because of auth (offline-first).
      debugPrint('AuthService: initialize failed, continuing offline: $e');
    }
  }

  /// False when Supabase credentials were not compiled in; auth UI then
  /// explains sync is unavailable instead of attempting network calls.
  bool get isConfigured => SupabaseConfig.isConfigured;

  String? _cachedOwnerId;
  StreamSubscription<AuthState>? _authSubscription;

  /// Last known Supabase user id (`auth.uid()` scope for Phase 0 RLS).
  ///
  /// Primary seam for the sync engine: stamp this on every upload. Null while
  /// signed out — sync must stay idle then. Survives restarts (mirrored to
  /// local storage at login / session restore, cleared on logout).
  String? get cachedOwnerId =>
      _cachedOwnerId ?? _clientOrNull?.auth.currentUser?.id;

  /// Currently signed-in user, or null. Available offline after a previous
  /// sign-in thanks to the SDK's persisted session.
  User? get currentUser => _clientOrNull?.auth.currentUser;

  /// Email of the signed-in user, shown in settings so users know which
  /// account their data syncs to. Null while signed out. For invited users
  /// this may be a synthesized address (see Phase 6); the phone in profiles
  /// is the human identifier.
  String? get currentUserEmail => currentUser?.email;

  /// Role copy from the auth token metadata (`app_metadata.role`, falling
  /// back to `user_metadata.role` for older invites). Null while signed out
  /// or when the copy is missing — callers must treat null as unprivileged.
  UserRole? get currentRole {
    final user = currentUser;
    if (user == null) return null;
    return UserRole.tryParse(
      (user.appMetadata['role'] ?? user.userMetadata?['role'])?.toString(),
    );
  }

  /// Emits the role copy on every auth-state change. Emits null while
  /// signed out or unconfigured.
  Stream<UserRole?> get currentRoleStream {
    final client = _clientOrNull;
    if (client == null) return Stream<UserRole?>.value(null);
    return client.auth.onAuthStateChange.map(
      (state) => UserRole.tryParse(
        (state.session?.user.appMetadata['role'] ??
                state.session?.user.userMetadata?['role'])
            ?.toString(),
      ),
    );
  }

  bool get isAdmin => currentRole == UserRole.admin;

  /// True when the signed-in user may manage the catalog (products, prices,
  /// price categories). Fail-open while signed out or when the role copy is
  /// missing: local editing keeps working offline-first and the database
  /// remains the real enforcer (see Phase 8 role RLS).
  bool get canEditCatalog {
    if (!isSignedIn) return true;
    final role = currentRole;
    return role == null || role == UserRole.admin;
  }

  /// True when the signed-in user may invite, resend, and recover users.
  /// Unlike [canEditCatalog] this is fail-closed: no role ⇒ no invite UI.
  bool get canManageUsers => isAdmin;

  /// True when a session is active.
  bool get isSignedIn => currentUser != null;

  /// Emits the current user on every auth-state change (sign-in, sign-out,
  /// token refresh, session restore). Emits `null` while signed out.
  /// When unconfigured, emits a single `null` and closes.
  Stream<User?> get currentUserStream {
    final client = _clientOrNull;
    if (client == null) return Stream<User?>.value(null);
    return client.auth.onAuthStateChange.map((state) {
      final id = state.session?.user.id;
      if (id != null) {
        unawaited(_persistOwnerId(id));
      } else {
        unawaited(_clearOwnerId());
      }
      return state.session?.user;
    });
  }

  /// Re-reads the SDK's persisted session (restored offline, no network) and
  /// refreshes [cachedOwnerId]. Safe to call on every startup.
  Future<void> restoreSession() async {
    final userId = _clientOrNull?.auth.currentUser?.id;
    if (userId != null) {
      await _persistOwnerId(userId);
    } else {
      await _loadPersistedOwnerId();
    }
    _listenToAuthChanges();
  }

  /// Creates an account and signs in. Throws [AuthNotConfiguredException],
  /// [AuthOfflineException], or [AuthFailureException].
  Future<void> signUp({required String email, required String password}) async {
    final client = _requireClient();
    await _requireOnline();
    try {
      final response = await client.auth.signUp(
        email: email,
        password: password,
      );
      await _persistOwnerId(response.user?.id);
    } on AuthException catch (e) {
      throw AuthFailureException(e.message);
    } on SocketException {
      throw const AuthOfflineException();
    }
  }

  /// Signs in with email and password. Throws [AuthNotConfiguredException],
  /// [AuthOfflineException], or [AuthFailureException].
  Future<void> signIn({required String email, required String password}) async {
    final client = _requireClient();
    await _requireOnline();
    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      await _persistOwnerId(response.user?.id ?? response.session?.user.id);
    } on AuthException catch (e) {
      throw AuthFailureException(e.message);
    } on SocketException {
      throw const AuthOfflineException();
    }
  }

  /// Signs out: clears the remote session and the cached owner id.
  /// Local business tables are deliberately untouched.
  /// Offline sign-out still clears local state (never strands a session).
  Future<void> signOut() async {
    try {
      await _clientOrNull?.auth.signOut();
    } on SocketException {
      // Offline: local session is still dropped below — logout always works.
      debugPrint('AuthService: sign-out offline, clearing local state.');
    } catch (e) {
      debugPrint('AuthService: sign-out error (clearing local state): $e');
    }
    await _clearOwnerId();
  }

  // -- internals ----------------------------------------------------------

  SupabaseClient? get _clientOrNull {
    if (!isConfigured) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      // Supabase.initialize() was never called — treat as signed out.
      return null;
    }
  }

  SupabaseClient _requireClient() {
    final client = _clientOrNull;
    if (client == null) throw const AuthNotConfiguredException();
    return client;
  }

  Future<void> _requireOnline() async {
    // Best-effort (see InviteService): a failing connectivity plugin must
    // never strand the user — the real call fails with AuthOfflineException.
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none) || results.isEmpty) {
        throw const AuthOfflineException();
      }
    } on PlatformException catch (e) {
      debugPrint('AuthService: connectivity check failed, proceeding: $e');
    }
  }

  /// Writes [ownerId] to memory + disk (null ⇒ skip). Best-effort on disk:
  /// the in-memory value still works for this session and the SDK session
  /// persists independently.
  Future<void> _persistOwnerId(String? ownerId) async {
    if (ownerId == null) return;
    _cachedOwnerId = ownerId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ownerIdPrefsKey, ownerId);
    } catch (e) {
      debugPrint('AuthService: owner-id cache write failed: $e');
    }
  }

  /// Clears memory + disk. Never touches business tables.
  Future<void> _clearOwnerId() async {
    _cachedOwnerId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(ownerIdPrefsKey);
    } catch (e) {
      debugPrint('AuthService: owner-id cache clear failed: $e');
    }
  }

  /// Startup path: picks up the last login's owner id when the SDK session
  /// is not (or not yet) available.
  Future<void> _loadPersistedOwnerId() async {
    if (_cachedOwnerId != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedOwnerId = prefs.getString(ownerIdPrefsKey);
    } catch (e) {
      debugPrint('AuthService: owner-id cache read failed: $e');
    }
  }

  void _listenToAuthChanges() {
    _authSubscription?.cancel();
    final client = _clientOrNull;
    if (client == null) return;
    _authSubscription = client.auth.onAuthStateChange.listen((state) {
      final id = state.session?.user.id;
      if (id != null) {
        unawaited(_persistOwnerId(id));
      } else {
        unawaited(_clearOwnerId());
      }
    });
  }
}
