import 'dart:convert';

import '../models/auth_models.dart';
import 'secure_store_service.dart';

class AuthStorageService {
  static const String _sessionKey = 'auth_session_v1';
  final SecureStoreService _secureStore;

  AuthStorageService({
    SecureStoreService? secureStore,
  }) : _secureStore = secureStore ?? const SecureStoreService();

  Future<void> saveSession(AuthSession session) async {
    await _secureStore.write(
      key: _sessionKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<AuthSession?> loadSession() async {
    final raw = await _secureStore.read(key: _sessionKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final session = AuthSession.fromJson(decoded);
        if (session.apiKey.isEmpty ||
            session.idToken.isEmpty ||
            session.refreshToken.isEmpty) {
          return null;
        }
        return session;
      }
      if (decoded is Map) {
        final normalized = decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final session = AuthSession.fromJson(normalized);
        if (session.apiKey.isEmpty ||
            session.idToken.isEmpty ||
            session.refreshToken.isEmpty) {
          return null;
        }
        return session;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> clearSession() async {
    await _secureStore.delete(key: _sessionKey);
  }
}
