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
}
