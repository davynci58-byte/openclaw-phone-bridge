import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Handles push-style notifications sent by OpenClaw.
class NotificationService {
  late FlutterLocalNotificationsPlugin _notifPlugin;

  Future<void> init() async {
    _notifPlugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _notifPlugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
  }

  /// Send a local notification (triggered by OpenClaw invoke).
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    bool playSound = true,
  }) async {
    await _notifPlugin.show(
      DateTime.now().millisecondsSinceEpoch % (1 << 31),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'openclaw_channel',
          'OpenClaw Notifications',
          channelDescription: 'Notifications from your OpenClaw agent',
          importance: Importance.high,
          priority: Priority.high,
          playSound: playSound,
          enableVibration: true,
          fullScreenIntent: false,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      payload: payload,
    );
    log('🔔 Notification: $title — $body');
  }

  void log(String msg) => debugPrint('🔔 [NotifSvc] $msg');
}
