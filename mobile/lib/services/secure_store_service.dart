import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

class SecureStoreService {
  const SecureStoreService();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> write({
    required String key,
    required String value,
  }) async {
    try {
      await _storage.write(key: key, value: value);
    } on MissingPluginException {
      // Fallback for test/runtime environments without secure-storage plugin.
    }
  }

  Future<String?> read({required String key}) async {
    try {
      return await _storage.read(key: key);
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> delete({required String key}) async {
    try {
      await _storage.delete(key: key);
    } on MissingPluginException {
      // Fallback for test/runtime environments without secure-storage plugin.
    }
  }
}
