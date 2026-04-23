import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/auth_models.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class FirebaseAuthService {
  final http.Client _client;

  FirebaseAuthService({http.Client? client})
      : _client = client ?? http.Client();

  Uri _verifyPasswordUri(String apiKey) {
    return Uri.parse(
      'https://www.googleapis.com/identitytoolkit/v3/relyingparty/verifyPassword?key=$apiKey',
    );
  }

  Uri _refreshUri(String apiKey) {
    return Uri.parse(
      'https://securetoken.googleapis.com/v1/token?key=$apiKey',
    );
  }

  Future<AuthSession> signInWithPassword({
    required String apiKey,
    required String email,
    required String username,
    required String password,
    required String backendBaseUrl,
  }) async {
    final normalizedApiKey = apiKey.trim();
    final normalizedEmail = email.trim();
    final normalizedUsername = username.trim();
    final normalizedBaseUrl = backendBaseUrl.trim();

    if (normalizedApiKey.isEmpty) {
      throw AuthException('Firebase API key is required.');
    }
    if (normalizedEmail.isEmpty) {
      throw AuthException('Email is required.');
    }
    if (normalizedUsername.isEmpty) {
      throw AuthException('Username is required.');
    }
    if (password.isEmpty) {
      throw AuthException('Password is required.');
    }
    if (normalizedBaseUrl.isEmpty) {
      throw AuthException('API base URL is required.');
    }

    final response = await _client.post(
      _verifyPasswordUri(normalizedApiKey),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(
        {
          'email': normalizedEmail,
          'password': password,
          'returnSecureToken': true,
        },
      ),
    );

    final payload = _decodeToMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(_firebaseErrorMessage(payload, response.statusCode));
    }

    final idToken = _asString(payload['idToken']);
    final refreshToken = _asString(payload['refreshToken']);
    if (idToken.isEmpty || refreshToken.isEmpty) {
      throw AuthException('Firebase response is missing idToken/refreshToken.');
    }

    final expiresAtMs = _computeExpiryMs(
      expiresIn: _asInt(payload['expiresIn']),
      fallbackToken: idToken,
    );

    return AuthSession(
      apiKey: normalizedApiKey,
      email: normalizedEmail,
      username: normalizedUsername,
      backendBaseUrl: normalizedBaseUrl,
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAtMs: expiresAtMs,
    );
  }

  Future<AuthSession> refreshSession(AuthSession current) async {
    if (current.apiKey.trim().isEmpty) {
      throw AuthException('Missing Firebase API key for refresh.');
    }
    if (current.refreshToken.trim().isEmpty) {
      throw AuthException('Missing refresh token.');
    }

    final response = await _client.post(
      _refreshUri(current.apiKey),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: Uri(
        queryParameters: {
          'grant_type': 'refresh_token',
          'refresh_token': current.refreshToken,
        },
      ).query,
    );

    final payload = _decodeToMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(_firebaseErrorMessage(payload, response.statusCode));
    }

    final idToken = _asString(payload['id_token']);
    if (idToken.isEmpty) {
      throw AuthException('Firebase refresh response is missing id_token.');
    }

    final refreshToken = _asString(payload['refresh_token']);
    final nextRefreshToken =
        refreshToken.isEmpty ? current.refreshToken : refreshToken;

    final expiresAtMs = _computeExpiryMs(
      expiresIn: _asInt(payload['expires_in']),
      fallbackToken: idToken,
    );

    return current.copyWith(
      idToken: idToken,
      refreshToken: nextRefreshToken,
      expiresAtMs: expiresAtMs,
    );
  }

  Map<String, dynamic> _decodeToMap(String rawBody) {
    if (rawBody.isEmpty) {
      return const {};
    }

    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return const {};
    }
    return const {};
  }

  String _firebaseErrorMessage(Map<String, dynamic> payload, int statusCode) {
    final error = payload['error'];
    if (error is Map<String, dynamic>) {
      final message = _asString(error['message']);
      if (message.isNotEmpty) {
        return 'Firebase auth failed ($statusCode): $message';
      }
    }
    return 'Firebase auth failed (HTTP $statusCode).';
  }

  int _computeExpiryMs({
    required int? expiresIn,
    required String fallbackToken,
  }) {
    if (expiresIn != null && expiresIn > 0) {
      return DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
    }
    return _decodeJwtExpMs(fallbackToken) ??
        DateTime.now().millisecondsSinceEpoch;
  }

  int? _decodeJwtExpMs(String token) {
    final parts = token.split('.');
    if (parts.length < 2) {
      return null;
    }

    final payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    final normalized =
        payload.padRight(payload.length + ((4 - payload.length % 4) % 4), '=');

    try {
      final body = utf8.decode(base64Decode(normalized));
      final json = jsonDecode(body);
      if (json is Map<String, dynamic> && json['exp'] is num) {
        return (json['exp'] as num).toInt() * 1000;
      }
      if (json is Map && json['exp'] is num) {
        return (json['exp'] as num).toInt() * 1000;
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

String _asString(dynamic value) => value?.toString() ?? '';

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
