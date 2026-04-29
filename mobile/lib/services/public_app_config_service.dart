import 'dart:convert';

import 'package:http/http.dart' as http;

class PublicAppConfigService {
  final http.Client _client;

  PublicAppConfigService({http.Client? client})
      : _client = client ?? http.Client();

  Future<String> fetchFirebaseApiKey(String backendBaseUrl) async {
    final normalizedBase = backendBaseUrl.trim();
    if (normalizedBase.isEmpty) {
      return '';
    }

    final baseWithoutSlash = normalizedBase.endsWith('/')
        ? normalizedBase.substring(0, normalizedBase.length - 1)
        : normalizedBase;
    final uri = Uri.parse('$baseWithoutSlash/public-config');
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return '';
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return '';
    }

    if (decoded['success'] != true) {
      return '';
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      return '';
    }

    final key = (data['firebaseApiKey'] ?? '').toString().trim();
    if (!key.startsWith('AIza')) {
      return '';
    }

    return key;
  }
}
