import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/api_models.dart';

typedef IdTokenProvider = Future<String?> Function({bool forceRefresh});

class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}

class BackendApiService {
  final String baseUrl;
  final http.Client _client;
  final IdTokenProvider? _idTokenProvider;

  BackendApiService({
    required this.baseUrl,
    http.Client? client,
    IdTokenProvider? idTokenProvider,
  })  : _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider;

  Uri _buildUri(String path, [Map<String, String>? query]) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$normalizedBase$normalizedPath');
    return uri.replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = _buildUri(path, query);
    var response = await _getWithOptionalAuth(uri);

    if (response.statusCode == 401 && _idTokenProvider != null) {
      response = await _getWithOptionalAuth(uri, forceRefresh: true);
    }

    return _decodeAndValidate(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = _buildUri(path, query);
    var response = await _postWithOptionalAuth(
      uri,
      body: body,
    );

    if (response.statusCode == 401 && _idTokenProvider != null) {
      response = await _postWithOptionalAuth(
        uri,
        body: body,
        forceRefresh: true,
      );
    }

    return _decodeAndValidate(response);
  }

  Future<http.Response> _getWithOptionalAuth(
    Uri uri, {
    bool forceRefresh = false,
  }) async {
    final headers = <String, String>{};
    final provider = _idTokenProvider;
    if (provider != null) {
      final token = await provider(forceRefresh: forceRefresh);
      final normalizedToken = token?.trim() ?? '';
      if (normalizedToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $normalizedToken';
      }
    }

    return _client.get(uri, headers: headers);
  }

  Future<http.Response> _postWithOptionalAuth(
    Uri uri, {
    Object? body,
    bool forceRefresh = false,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    final provider = _idTokenProvider;
    if (provider != null) {
      final token = await provider(forceRefresh: forceRefresh);
      final normalizedToken = token?.trim() ?? '';
      if (normalizedToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $normalizedToken';
      }
    }

    return _client.post(
      uri,
      headers: headers,
      body: jsonEncode(body ?? const {}),
    );
  }

  Map<String, dynamic> _decodeAndValidate(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Invalid response format');
    }

    if (decoded['success'] != true) {
      final detail = decoded['detail']?.toString();
      final err = decoded['error']?.toString() ?? 'Request failed';
      throw ApiException(
          detail != null && detail.isNotEmpty ? '$err - $detail' : err);
    }

    return decoded;
  }

  Future<List<ClassSummary>> getClasses({
    bool activeOnly = true,
    int itemsPerPage = 50,
    int maxPages = 10,
    String? username,
  }) async {
    final query = <String, String>{
      'activeOnly': activeOnly.toString(),
      'itemsPerPage': itemsPerPage.toString(),
      'maxPages': maxPages.toString(),
    };
    if (username != null && username.trim().isNotEmpty) {
      query['username'] = username.trim();
    }

    final json = await _getJson('/classes', query: query);

    final data = json['data'];
    if (data is! List) {
      return const [];
    }

    return data
        .whereType<Map>()
        .map((e) => ClassSummary.fromJson(
              e.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList();
  }

  Future<List<ReminderItem>> getAttendanceReminders({
    int lookAheadMinutes = 180,
    int maxSlots = 20,
    bool activeOnly = true,
    String? username,
  }) async {
    final query = <String, String>{
      'lookAheadMinutes': lookAheadMinutes.toString(),
      'maxSlots': maxSlots.toString(),
      'activeOnly': activeOnly.toString(),
    };
    if (username != null && username.trim().isNotEmpty) {
      query['username'] = username.trim();
    }

    final json = await _getJson('/attendance-reminders', query: query);

    final data = json['data'];
    if (data is! List) {
      return const [];
    }

    return data
        .whereType<Map>()
        .map((e) => ReminderItem.fromJson(
              e.map((key, value) => MapEntry(key.toString(), value)),
            ))
        .toList();
  }

  Future<PayrollResponse> getMonthlyPayroll({
    required int month,
    required int year,
    String? username,
    String timezone = 'Asia/Ho_Chi_Minh',
    String countedStatuses = 'ATTENDED,LATE_ARRIVED',
  }) async {
    final query = <String, String>{
      'month': month.toString(),
      'year': year.toString(),
      'timezone': timezone,
      'countedStatuses': countedStatuses,
    };
    if (username != null && username.trim().isNotEmpty) {
      query['username'] = username.trim();
    }

    final json = await _getJson('/payroll/monthly', query: query);
    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw ApiException('Invalid payroll response');
    }

    return PayrollResponse.fromJson(data);
  }

  Future<AttendanceSaveResult> saveSlotAttendance({
    required String classId,
    required String slotId,
    required List<AttendanceSaveParticipant> participants,
  }) async {
    final json = await _postJson(
      '/attendance/slot',
      body: {
        'classId': classId,
        'slotId': slotId,
        'participants': participants.map((item) => item.toJson()).toList(),
      },
    );

    final data = json['data'];
    if (data is! Map<String, dynamic>) {
      throw ApiException('Invalid attendance save response');
    }

    return AttendanceSaveResult.fromJson(data);
  }
}
