/// Build-time configuration. The only file that reads `--dart-define`s.
/// Defaults point at the production project; its URL and publishable key
/// are public by design.
abstract final class Environment() {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jdwqrallbpdbshrdhenk.supabase.co',
  );
  static const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_YMFUFoZ-smly3zDIYTIFRw_vRt6UBk5',
  );

  /// Public web origin for invite links from the mobile apps; empty shows
  /// only the code.
  static const appUrl = String.fromEnvironment('APP_URL');

  /// Path the web app is served under, e.g. `/family-groceries` on GitHub
  /// Pages; empty at the domain root. Must match the build's `--base-href`.
  static const webBasePath = String.fromEnvironment('WEB_BASE_PATH');

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

/// Where this web app lives: origin plus [Environment.webBasePath].
String get webRoot => '${Uri.base.origin}${Environment.webBasePath}';
