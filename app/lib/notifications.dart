/// 本地通知服务（新消息 / 好友请求提醒）。
/// - Android / iOS：flutter_local_notifications
/// - Windows / macOS / Linux：local_notifier（系统通知中心弹窗）
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';

class AppNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    if (_isDesktop) {
      try {
        await localNotifier.setup(
          appName: '萨摩聊天',
          // Windows：首次运行自动创建开始菜单快捷方式（系统通知需要它来注册）
          shortcutPolicy: ShortcutPolicy.requireCreate,
        );
      } catch (_) {}
      return;
    }
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios),
      );
    } catch (_) {}
  }

  /// 请求通知权限（Android 13+ / iOS；桌面无需申请）。
  static Future<void> requestPermissions() async {
    if (_isDesktop) return;
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
  }

  static Future<void> showMessage({
    required String title,
    required String body,
    int id = 0,
  }) async {
    if (_isDesktop) {
      try {
        await LocalNotification(title: title, body: body).show();
      } catch (_) {}
      return;
    }
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'sama_messages',
          '消息通知',
          channelDescription: '收到新消息时提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );
      await _plugin.show(id, title, body, details);
    } catch (_) {}
  }
}
