import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:i_gen/auth/auth_exceptions.dart';
import 'package:i_gen/auth/auth_service.dart';

/// How the invite pipe was used. Mirrors the server function's `mode`.
enum InviteMode {
  invite,
  resend,
  recovery;

  String get wire => name;
}

/// Result of an invite/resend/recovery call: the synthesized login plus the
/// one-time link the admin forwards over WhatsApp. The link itself is the
/// only secret — it is single-use and short-lived.
class InviteResult {
  const InviteResult({
    required this.fakeEmail,
    required this.actionLink,
    required this.mode,
  });

  factory InviteResult.fromJson(Map<String, dynamic> json, InviteMode mode) {
    return InviteResult(
      fakeEmail: (json['fake_email'] ?? '').toString(),
      actionLink: (json['action_link'] ?? '').toString(),
      mode: mode,
    );
  }

  final String fakeEmail;
  final String actionLink;
  final InviteMode mode;
}

/// Client for the admin-only `invite-user` function (Phase 7).
///
/// Thin by design: validation, uniqueness, link generation, and the profiles
/// write all live server-side. This only forwards the four admin-supplied
/// fields and maps failures to UI-ready auth exceptions. Reuses the
/// authentication module's online-check behavior.
class InviteService {
  InviteService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client {
    final override = _clientOverride;
    if (override != null) return override;
    return Supabase.instance.client;
  }

  /// Deterministic preview of the synthesized email slug (server appends a
  /// random suffix only on collision). Typo-catching aid, not the identity.
  static String slugPreview(String nameEn) {
    final slug = nameEn
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');
    return slug.isEmpty ? 'user' : slug;
  }

  Future<InviteResult> send({
    required String nameAr,
    required String nameEn,
    required String phone,
    required UserRole role,
    InviteMode mode = InviteMode.invite,
  }) async {
    await _requireOnline();
    if (role == UserRole.admin) {
      throw const AuthFailureException(
        'New admins are bootstrapped, not invited.',
      );
    }
    try {
      // functions.invoke sends only the anon key — attach the login token
      // explicitly or the function cannot tell who is calling (401).
      final accessToken = _client.auth.currentSession?.accessToken;
      final response = await _client.functions.invoke(
        'invite-user',
        body: {
          'name_ar': nameAr.trim(),
          'name_en': nameEn.trim(),
          'phone': phone.trim(),
          'role': role.name,
          'mode': mode.wire,
        },
        headers: {
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
      );
      final data = response.data;
      if (data is Map && data['error'] is String) {
        throw AuthFailureException(data['error'] as String);
      }
      if (data is! Map<String, dynamic>) {
        throw const AuthFailureException(
          'Unexpected invite response — try again.',
        );
      }
      final result = InviteResult.fromJson(data, mode);
      if (result.actionLink.isEmpty || result.fakeEmail.isEmpty) {
        throw const AuthFailureException(
          'Invite link came back empty — try again.',
        );
      }
      return result;
    } on AuthFailureException {
      rethrow;
    } on SocketException {
      throw const AuthOfflineException();
    } catch (e) {
      debugPrint('InviteService: invite call failed: $e');
      throw AuthFailureException('Could not reach the invite service: $e');
    }
  }

  /// Accepts a WhatsApp invite/recovery link in any shape Supabase may
  /// deliver it: the raw `token_hash` action link, the post-verification
  /// redirect carrying a PKCE `code`, or an implicit-flow fragment with
  /// tokens. Server-side error redirects surface the ask-admin message.
  /// Returns true when the link established a session that still needs a
  /// password (fresh invite) — the caller must then show password setup.
  Future<bool> acceptLink(String rawLink) async {
    await _requireOnline();
    final uri = Uri.tryParse(rawLink.trim());
    if (uri == null) {
      throw const AuthFailureException(
        'That link does not look valid — check the pasted text.',
      );
    }
    final params = uri.queryParameters;
    // Supabase redirects failures back with error params instead of tokens.
    final redirectError = params['error_description'] ?? params['error'] ?? '';
    if (redirectError.isNotEmpty) {
      if (redirectError.toLowerCase().contains('expired')) {
        throw const AuthFailureException(
          'Link expired — ask the admin for a new one.',
        );
      }
      throw AuthFailureException(redirectError);
    }
    // PKCE shape: post-verification redirect appends ?code=.
    final code = params['code'] ?? '';
    if (code.isNotEmpty) {
      try {
        await _client.auth.exchangeCodeForSession(code);
        return true;
      } on AuthException catch (e) {
        throw _linkFailure(e.message);
      } on SocketException {
        throw const AuthOfflineException();
      }
    }
    // Implicit shape: tokens arrive in the fragment, not the query.
    final fragmentParams = Uri.splitQueryString(uri.fragment);
    final refreshToken = fragmentParams['refresh_token'] ?? '';
    if ((fragmentParams['access_token'] ?? '').isNotEmpty &&
        refreshToken.isNotEmpty) {
      try {
        await _client.auth.setSession(refreshToken);
        return true;
      } on AuthException catch (e) {
        throw _linkFailure(e.message);
      } on SocketException {
        throw const AuthOfflineException();
      }
    }
    final tokenHash = params['token_hash'] ?? params['token'] ?? '';
    final type = (params['type'] ?? 'invite').toLowerCase();
    if (tokenHash.isEmpty) {
      throw const AuthFailureException(
        'That link has no token — ask the admin for a fresh one.',
      );
    }
    try {
      final otpType = type == 'recovery' ? OtpType.recovery : OtpType.invite;
      final response = await _client.auth.verifyOTP(
        tokenHash: tokenHash,
        type: otpType,
      );
      // A fresh invite verifies the address and signs the user in with no
      // password yet — password setup is the mandatory next step.
      return otpType == OtpType.invite && response.session != null;
    } on AuthException catch (e) {
      throw _linkFailure(e.message);
    } on SocketException {
      throw const AuthOfflineException();
    }
  }

  AuthFailureException _linkFailure(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('expired') || lower.contains('invalid')) {
      return const AuthFailureException(
        'Link expired — ask the admin for a new one.',
      );
    }
    return AuthFailureException(message);
  }

  /// Sets the password for the session established by [acceptLink].
  /// Completes onboarding for fresh invites; also serves as the
  /// no-email password change for signed-in users.
  Future<void> setPassword(String password) async {
    await _requireOnline();
    if (password.length < 6) {
      throw const AuthFailureException(
        'Password must be at least 6 characters.',
      );
    }
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (e) {
      throw AuthFailureException(e.message);
    } on SocketException {
      throw const AuthOfflineException();
    }
  }

  Future<void> _requireOnline() async {
    // Best-effort: on platforms where the connectivity plugin itself fails
    // (e.g. Windows NetworkManager listener), proceed and let the real
    // network call fail with AuthOfflineException instead of stranding
    // the user on a plugin bug.
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.contains(ConnectivityResult.none) || results.isEmpty) {
        throw const AuthOfflineException();
      }
    } on PlatformException catch (e) {
      debugPrint('InviteService: connectivity check failed, proceeding: $e');
    }
  }
}
