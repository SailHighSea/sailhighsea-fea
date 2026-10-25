/// Supabase project settings. They come from `--dart-define-from-file=.env.json` (gitignored),
/// never from source (rule 10). Without them the app runs local-only, exactly as in Phase 2.
class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  /// Read at compile time from `--dart-define`.
  const SupabaseConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      anonKey = const String.fromEnvironment('SUPABASE_ANON_KEY');

  final String url;
  final String anonKey;

  bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}

/// Where the sign-in emails and OAuth providers send people back to the app. Add this to the
/// Supabase redirect URLs (supabase/README.md).
const authRedirectUrl = 'app.familyexpenses://login-callback';
