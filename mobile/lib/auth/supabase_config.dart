/// Compile-time Supabase configuration (Phase 1).
///
/// The project URL and anon key are supplied via `--dart-define` so no secret
/// lives in source control. The anon key is public by design (RLS in
/// supabase/phase-0-schema.sql is what protects user data).
///
/// Example:
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xyzcompany.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
///
/// When either value is missing the app runs exactly as before login existed:
/// fully usable offline, with the settings login UI explaining that sync is
/// not configured.
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// Publishable key (falls back to the legacy `SUPABASE_ANON_KEY` define;
  /// both values work — only the SDK parameter name changed).
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  /// True once both values are provided. False ⇒ auth/sync stay dormant.
  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;
}
