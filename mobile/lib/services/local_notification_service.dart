import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  static const String _channelId = 'lms_comment_reminders_v1';
  static const String _channelName = 'Nhac nho LMS';
  static const String _channelDescription =
      'Thong bao cac lop con thieu nhan xet hoac can xu ly';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  bool _didRequestPermission = false;

  bool get _supportsLocalNotification =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  Future<void> _ensureInitialized() async {
    if (_isInitialized || !_supportsLocalNotification) {
      return;
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      macOS: iosInit,
    );

    await _plugin.initialize(initializationSettings);

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
        ),
      );
    }

    _isInitialized = true;
  }

  Future<void> _requestPermissionIfNeeded() async {
    if (_didRequestPermission || !_supportsLocalNotification) {
      return;
    }
    _didRequestPermission = true;

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    final macImpl = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    await macImpl?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> showPendingCommentReminder({
    required int classCount,
    required int missingCommentCount,
    required List<String> classNames,
  }) async {
    if (classCount <= 0 || !_supportsLocalNotification) {
      return;
    }

    try {
      await _ensureInitialized();
      await _requestPermissionIfNeeded();

      final title = 'Ban co $classCount lop chua nhan xet';
      final classHint = classNames.take(2).join(', ');
      final body = classHint.isEmpty
          ? 'Con $missingCommentCount nhan xet can xu ly. Mo app de cap nhat.'
          : '$classHint... Con $missingCommentCount nhan xet can xu ly.';

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
          macOS: iosDetails,
        ),
        payload: 'pending_comment_reminder',
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Local notification error: $error');
      }
    }
  }
}
