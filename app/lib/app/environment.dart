/// Build-time configuration. The only file that reads `--dart-define`s.
/// Defaults point at the production project; its URL and publishable key
/// are public by design.
abstract final class Environment() {
  static const _productionSupabaseUrl =
      'https://jdwqrallbpdbshrdhenk.supabase.co';
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _productionSupabaseUrl,
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_YMFUFoZ-smly3zDIYTIFRw_vRt6UBk5',
  );

  /// Public web origin for invite links from the mobile apps; empty shows
  /// only the code. Production builds link to the Vercel app; builds against
  /// another project (local stack) show only the code.
  static const appUrl = String.fromEnvironment(
    'APP_URL',
    defaultValue: supabaseUrl == _productionSupabaseUrl
        ? 'https://family-groceries-pied.vercel.app'
        : '',
  );

  /// Google OAuth "Web application" client ID. Supabase verifies ID tokens
  /// against it and native sign-in passes it as the server client ID; empty
  /// hides the Google button.
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
  );

  /// Google OAuth "iOS" client ID; empty hides the Google button on iOS.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Whether the Supabase project has Sign in with Apple configured.
  static const signInWithApple = bool.fromEnvironment('SIGN_IN_WITH_APPLE');

  /// The MCP server endpoint, an edge function of the same project.
  static const mcpUrl = '$supabaseUrl/functions/v1/mcp';
}

/// Where this web app lives; it is always served at the domain root.
String get webRoot => Uri.base.origin;
