import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:uuid/uuid.dart';
import '../models/alarm.dart';
import 'storage_service.dart';

/// Manages device alarms and schedules local notifications.
class AlarmService extends ChangeNotifier {
  final StorageService _storage;
  final _uuid = const Uuid();
  late FlutterLocalNotificationsPlugin _notifPlugin;

  List<DeviceAlarm> _alarms = [];
  Timer? _checkTimer;

  void Function(DeviceAlarm alarm)? onAlarmFired;

  List<DeviceAlarm> get alarms => List.unmodifiable(_alarms);

  AlarmService({required StorageService storage}) : _storage = storage;

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

    _alarms = _storage.getAlarms();
    _startAlarmChecker();
    notifyListeners();
  }

  Future<DeviceAlarm> addAlarm({
    required String label,
    required AlarmTime time,
    List<bool>? repeatDays,
    int snoozeMinutes = 5,
  }) async {
    final alarm = DeviceAlarm(
      id: _uuid.v4(),
      label: label,
      time: time,
      repeatDays: repeatDays ?? List.filled(7, false),
      enabled: true,
      snoozeMinutes: snoozeMinutes,
    );
    await _storage.saveAlarm(alarm);
    _alarms.add(alarm);
    _alarms.sort((a, b) => a.time.totalMinutes.compareTo(b.time.totalMinutes));
    _scheduleAlarmNotification(alarm);
    notifyListeners();
    return alarm;
  }

  Future<DeviceAlarm> updateAlarm(DeviceAlarm alarm) async {
    await _storage.saveAlarm(alarm);
    final idx = _alarms.indexWhere((a) => a.id == alarm.id);
    if (idx >= 0) {
      _alarms[idx] = alarm;
    } else {
      _alarms.add(alarm);
    }
    _scheduleAlarmNotification(alarm);
    notifyListeners();
    return alarm;
  }

  Future<void> removeAlarm(String id) async {
    await _storage.deleteAlarm(id);
    _alarms.removeWhere((a) => a.id == id);
    _notifPlugin.cancel(id.hashCode);
    notifyListeners();
  }

  Future<void> toggleAlarm(String id) async {
    final idx = _alarms.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final updated = _alarms[idx].copyWith(enabled: !_alarms[idx].enabled);
    await updateAlarm(updated);
  }

  void _startAlarmChecker() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkDueAlarms();
    });
  }

  void _checkDueAlarms() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;

    for (final alarm in _alarms) {
      if (!alarm.enabled) continue;
      if (alarm.time.totalMinutes != currentMinutes) continue;

      final today = now.weekday == 7 ? 0 : now.weekday;
      if (alarm.repeatDays.any((d) => d)) {
        if (!alarm.repeatDays[today]) continue;
      }
      _fireAlarm(alarm);
    }
  }

  void _fireAlarm(DeviceAlarm alarm) {
    log('⏰ ALARM: ${alarm.label}');
    onAlarmFired?.call(alarm);

    _notifPlugin.show(
      alarm.id.hashCode,
      '⏰ ${alarm.label}',
      'Alarm is ringing!',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'alarm_channel',
          'Alarms',
          channelDescription: 'Phone alarm notifications',
          importance: Importance.high,
          priority: Priority.high,
          fullScreenIntent: true,
          playSound: true,
          enableVibration: true,
          actions: [
            AndroidNotificationAction('snooze', 'Snooze'),
            AndroidNotificationAction('dismiss', 'Dismiss'),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
  }

  void _scheduleAlarmNotification(DeviceAlarm alarm) {
    if (!alarm.enabled) return;
    // The periodic checker (every 30s) handles firing.
    // This method is kept for future advanced scheduling via Android AlarmManager.
    // Notifications will be shown at alarm time from _checkDueAlarms.
  }

  void log(String msg) => debugPrint('🔔 $msg');

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }
}
