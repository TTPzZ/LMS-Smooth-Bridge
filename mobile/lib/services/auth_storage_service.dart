import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_models.dart';

class AuthStorageService {
  static const String _sessionKey = 'auth_session_v1';

  Future<void> saveSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<AuthSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
