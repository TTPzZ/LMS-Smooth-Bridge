class AuthSession {
  final String apiKey;
  final String email;
  final String backendBaseUrl;
  final String idToken;
  final String refreshToken;
  final int expiresAtMs;

  const AuthSession({
    required this.apiKey,
    required this.email,
    required this.backendBaseUrl,
    required this.idToken,
    required this.refreshToken,
    required this.expiresAtMs,
  });

  bool get isExpiredSoon {
    final thresholdMs = DateTime.now().millisecondsSinceEpoch + 60 * 1000;
    return expiresAtMs <= thresholdMs;
  }

  DateTime get expiresAt => DateTime.fromMillisecondsSinceEpoch(expiresAtMs);

  AuthSession copyWith({
    String? apiKey,
    String? email,
    String? backendBaseUrl,
    String? idToken,
    String? refreshToken,
    int? expiresAtMs,
  }) {
    return AuthSession(
      apiKey: apiKey ?? this.apiKey,
      email: email ?? this.email,
      backendBaseUrl: backendBaseUrl ?? this.backendBaseUrl,
      idToken: idToken ?? this.idToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'apiKey': apiKey,
      'email': email,
      'backendBaseUrl': backendBaseUrl,
      'idToken': idToken,
      'refreshToken': refreshToken,
      'expiresAtMs': expiresAtMs,
    };
  }

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      apiKey: (json['apiKey'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      backendBaseUrl: (json['backendBaseUrl'] ?? '').toString(),
      idToken: (json['idToken'] ?? '').toString(),
      refreshToken: (json['refreshToken'] ?? '').toString(),
      expiresAtMs: _asInt(json['expiresAtMs']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
