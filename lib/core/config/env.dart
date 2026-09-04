// Central environment configuration. Values are injected at build time via
// --dart-define (see README). NEVER hard-code real keys here.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  static void assertConfigured() {
    assert(supabaseUrl.isNotEmpty, 'SUPABASE_URL not provided via --dart-define');
    assert(supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY not provided via --dart-define');
  }
}
