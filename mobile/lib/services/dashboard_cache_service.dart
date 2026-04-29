import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_models.dart';

class DashboardCacheService {
  static const String _prefix = 'dashboard_cache_v3';

  Future<List<ClassSummary>?> loadClasses({
    required String username,
    required Duration maxAge,
  }) async {
    final payload = await _loadJson(
      _key(username, 'classes'),
      _key(username, 'classes.savedAtMs'),
      maxAge,
    );
    if (payload is! List) {
      return null;
    }

    return payload
        .whereType<Map>()
        .map(
          (item) => ClassSummary.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<void> saveClasses({
    required String username,
    required List<ClassSummary> classes,
  }) async {
    await _saveJson(
      _key(username, 'classes'),
      _key(username, 'classes.savedAtMs'),
      classes.map((item) => item.toJson()).toList(),
    );
  }

  Future<List<ReminderItem>?> loadReminders({
    required String username,
    required Duration maxAge,
  }) async {
    final payload = await _loadJson(
      _key(username, 'reminders'),
      _key(username, 'reminders.savedAtMs'),
      maxAge,
    );
    if (payload is! List) {
      return null;
    }

    return payload
        .whereType<Map>()
        .map(
          (item) => ReminderItem.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  Future<void> saveReminders({
    required String username,
    required List<ReminderItem> reminders,
  }) async {
    await _saveJson(
      _key(username, 'reminders'),
      _key(username, 'reminders.savedAtMs'),
      reminders.map((item) => item.toJson()).toList(),
    );
  }

  Future<PayrollResponse?> loadPayroll({
    required String username,
    required int month,
    required int year,
    required Duration maxAge,
  }) async {
    final payload = await _loadJson(
      _key(username, 'payroll.$year.$month'),
      _key(username, 'payroll.$year.$month.savedAtMs'),
      maxAge,
    );
    if (payload is! Map) {
      return null;
    }

    return PayrollResponse.fromJson(
      payload.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<void> savePayroll({
    required String username,
    required PayrollResponse payroll,
  }) async {
    await _saveJson(
      _key(username, 'payroll.${payroll.year}.${payroll.month}'),
      _key(username, 'payroll.${payroll.year}.${payroll.month}.savedAtMs'),
      payroll.toJson(),
    );
  }

  Future<dynamic> _loadJson(
    String payloadKey,
    String savedAtKey,
    Duration maxAge,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final savedAtMs = prefs.getInt(savedAtKey);
    if (savedAtMs == null) {
      return null;
    }

    final ageMs = DateTime.now().millisecondsSinceEpoch - savedAtMs;
    if (ageMs > maxAge.inMilliseconds) {
      return null;
    }

    final raw = prefs.getString(payloadKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveJson(
    String payloadKey,
    String savedAtKey,
    dynamic payload,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(payloadKey, jsonEncode(payload));
    await prefs.setInt(savedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  String _key(String username, String suffix) {
    final normalized = username.trim().toLowerCase();
    final scope = normalized.isEmpty ? 'default' : normalized;
    return '$_prefix.$scope.$suffix';
  }
}
