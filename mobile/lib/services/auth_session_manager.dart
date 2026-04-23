import '../models/auth_models.dart';
import 'auth_storage_service.dart';
import 'firebase_auth_service.dart';

class AuthSessionManager {
  final FirebaseAuthService _authService;
  final AuthStorageService _storageService;
  AuthSession? _session;

  AuthSessionManager({
    FirebaseAuthService? authService,
    AuthStorageService? storageService,
  })  : _authService = authService ?? FirebaseAuthService(),
        _storageService = storageService ?? AuthStorageService();

  AuthSession? get currentSession => _session;

  Future<AuthSession?> restoreSession() async {
    final storedSession = await _storageService.loadSession();
    if (storedSession == null) {
      _session = null;
      return null;
    }

    _session = storedSession;
    try {
      final refreshed =
          await ensureSession(forceRefresh: storedSession.isExpiredSoon);
      return refreshed;
    } catch (_) {
      await signOut();
      return null;
    }
  }

  Future<AuthSession> signIn({
    required String apiKey,
    required String email,
    required String password,
    required String backendBaseUrl,
  }) async {
    final session = await _authService.signInWithPassword(
      apiKey: apiKey,
      email: email,
      password: password,
      backendBaseUrl: backendBaseUrl,
    );
    _session = session;
    await _storageService.saveSession(session);
    return session;
  }

  Future<AuthSession> ensureSession({bool forceRefresh = false}) async {
    final current = _session;
    if (current == null) {
      throw AuthException('No active session.');
    }

    if (!forceRefresh && !current.isExpiredSoon) {
      return current;
    }

    final refreshed = await _authService.refreshSession(current);
    _session = refreshed;
    await _storageService.saveSession(refreshed);
    return refreshed;
  }

  Future<String?> getValidIdToken({bool forceRefresh = false}) async {
    final session = _session;
    if (session == null) {
      return null;
    }

    final ensured = await ensureSession(forceRefresh: forceRefresh);
    return ensured.idToken;
  }

  Future<AuthSession> updateBackendBaseUrl(String backendBaseUrl) async {
    final session = _session;
    if (session == null) {
      throw AuthException('No active session.');
    }

    final normalizedBaseUrl = backendBaseUrl.trim();
    if (normalizedBaseUrl.isEmpty) {
      throw AuthException('API base URL is required.');
    }

    final updated = session.copyWith(backendBaseUrl: normalizedBaseUrl);
    _session = updated;
    await _storageService.saveSession(updated);
    return updated;
  }

  Future<void> signOut() async {
    _session = null;
    await _storageService.clearSession();
  }
}
