class AppConfig {
  static const String apiBaseUrl = 'https://lms-smooth-bridge.vercel.app/api';

  // Provide at runtime/build time with:
  // --dart-define=FIREBASE_API_KEY=...
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );

  static bool get hasFirebaseApiKey {
    final value = firebaseApiKey.trim();
    return value.isNotEmpty && value.startsWith('AIza');
  }
}
