class AppConfig {
  static const String apiBaseUrl = 'https://lms-smooth-bridge.vercel.app/api';

  // Hardcoded key for your app build.
  static const String embeddedFirebaseApiKey =
      'AIzaSyAh2Au-mk5ci-hN83RUBqj1fsAmCMdvJx4';

  // Optional override when running with:
  // --dart-define=FIREBASE_API_KEY=...
  static const String firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: embeddedFirebaseApiKey,
  );

  static bool get hasFirebaseApiKey {
    final value = firebaseApiKey.trim();
    return value.isNotEmpty && value.startsWith('AIza');
  }
}
