import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
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
  final Set<String> _firedAlarmKeys = {};

  /// Callback when an alarm fires (for OpenClaw event).
  void Function(DeviceAlarm alarm)? onAlarmFired;

  List<DeviceAlarm> get alarms => List.unmodifiable(_alarms);

  AlarmService({required StorageService storage}) : _storage = storage;

  // ── Init ──────────────────────────────────────────────────────────

  Future<void> init() async {
    _notifPlugin = FlutterLocalNotificationsPlugin();
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _notifPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _alarms = _storage.getAlarms();
    _startAlarmChecker();
    notifyListeners();
  }

  // ── CRUD ──────────────────────────────────────────────────────────

  Future<DeviceAlarm> addAlarm({
    required String label,
    required TimeOfDay time,
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

  Future<void> snoozeAlarm(String id, {int minutes = 5}) async {
    final idx = _alarms.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    // Schedule a delayed notification
    final snoozeTime = DateTime.now().add(Duration(minutes: minutes));
    await _scheduleNotif(
      id: 'snooze_$id',
      title: '${_alarms[idx].label} (Snoozed)',
      body: 'Alarm snoozed for $minutes min',
      scheduledAt: snoozeTime,
    );
  }

  // ── Alarm Checker ─────────────────────────────────────────────────

  void _startAlarmChecker() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkDueAlarms();
    });
  }

  void _checkDueAlarms() {
    final now = DateTime.now();
    final currentMinutes = now.hour * 60 + now.minute;
    // Build a key for this minute to prevent duplicate fires
    final minuteKey = '${now.year}-${now.month}-${now.day}-$currentMinutes';

    for (final alarm in _alarms) {
      if (!alarm.enabled) continue;
      if (alarm.time.totalMinutes != currentMinutes) continue;

      // Check if today is a repeat day or if it's a one-off
      final today = now.weekday == 7 ? 0 : now.weekday; // Sun = 0
      if (alarm.repeatDays.any((d) => d)) {
        if (!alarm.repeatDays[today]) continue;
      }

      // Skip if this alarm already fired in this minute
      final alarmKey = '$minuteKey-${alarm.id}';
      if (_firedAlarmKeys.contains(alarmKey)) continue;
      _firedAlarmKeys.add(alarmKey);

      // Clean up old minute keys to avoid memory leak
      if (_firedAlarmKeys.length > 100) {
        _firedAlarmKeys.removeWhere((k) => !k.startsWith(minuteKey.substring(0, 10)));
      }

      // Fire alarm
      _fireAlarm(alarm);
    }
  }

  void _fireAlarm(DeviceAlarm alarm) {
    log('⏰ ALARM: ${alarm.label}');
    onAlarmFired?.call(alarm);

    // Show notification
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
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
    );
  }

  // ── Scheduled Notifications ───────────────────────────────────────

  void _scheduleAlarmNotification(DeviceAlarm alarm) {
    if (!alarm.enabled) return;
    final scheduledAt = alarm.time.nextOccurrence(DateTime.now());
    final hasRepeat = alarm.repeatDays.any((d) => d);
    _scheduleNotif(
      id: alarm.id,
      title: '⏰ ${alarm.label}',
      body: 'Your alarm at ${alarm.timeFormatted}',
      scheduledAt: scheduledAt,
      matchDateTimeComponents: hasRepeat
          ? DateTimeComponents.dayOfWeekAndTime
          : DateTimeComponents.time,
    );
  }

  Future<void> _scheduleNotif({
    required String id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    final now = DateTime.now();
    final diff = scheduledAt.difference(now);
    if (diff.isNegative || diff.inMinutes < 1) return;

    // Cancel existing first
    _notifPlugin.cancel(id.hashCode);

    // Use TZDateTime.utc() — no timezone database needed
    final tzScheduled = tz.TZDateTime.utc(
      scheduledAt.year,
      scheduledAt.month,
      scheduledAt.day,
      scheduledAt.hour,
      scheduledAt.minute,
      scheduledAt.second,
    );

    await _notifPlugin.zonedSchedule(
      id.hashCode,
      title,
      body,
      tzScheduled,
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
          actions: <AndroidNotificationAction>[
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
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: matchDateTimeComponents,
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    log('Notification tapped: ${response.payload}');
    // Could navigate to alarm screen
  }

  void log(String msg) => debugPrint('🔔 [AlarmSvc] $msg');

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }
}
