/// Server settings baked into the build:
///   flutter build apk --dart-define-from-file=env.json
/// with env.json = {"SUPABASE_URL": "...", "SUPABASE_ANON_KEY": "..."}.
/// When they are empty the app asks for them on first start instead.
/// What the "المزيد" screen shows at the bottom. Kept next to the build
/// settings so it is changed with the version in pubspec.yaml and nowhere
/// else.
const appVersion = '2.9.0';

class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
