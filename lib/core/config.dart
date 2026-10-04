/// What the "المزيد" screen shows at the bottom. Kept next to the build
/// settings so it is changed with the version in pubspec.yaml and nowhere
/// else.
const appVersion = '3.0.0';

/// The company server, built into the app.
///
/// Nobody in the family types a URL or a key: they install the APK, write
/// their name, and they are in. The owner changes the two values below when
/// the project or the key changes, and builds again.
///
/// The key here is the **publishable** key (`sb_publishable_…`, the old
/// `anon` key). It is meant to sit inside client apps: what it can read or
/// write is decided by the row level security policies on the server, which
/// is why it is safe in a build and in the repository. The **secret** key
/// (`service_role`) must never be put in the app, in a file here, or in a
/// build — it ignores those policies.
///
/// A build can still override them without touching this file:
///   flutter build apk --dart-define-from-file=env.json
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://epyfhbkpesqciwpaltwo.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_VXphqgTEmzq-m7aL8gCnMQ_As1vP3-s',
  );

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
