import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/calendar_event.dart';
import '../models/alarm.dart';

/// Persists calendar events and alarms locally via SharedPreferences.
class StorageService {
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  // ── Calendar Events ───────────────────────────────────────────────

  List<CalendarEvent> getCalendarEvents() {
    final json = _prefs.getString('calendar_events');
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<void> saveCalendarEvent(CalendarEvent event) async {
    final events = getCalendarEvents();
    final idx = events.indexWhere((e) => e.id == event.id);
    if (idx >= 0) {
      events[idx] = event;
    } else {
      events.add(event);
    }
    await _prefs.setString(
      'calendar_events',
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> deleteCalendarEvent(String id) async {
    final events = getCalendarEvents()..removeWhere((e) => e.id == id);
    await _prefs.setString(
      'calendar_events',
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  // ── Alarms ────────────────────────────────────────────────────────

  List<DeviceAlarm> getAlarms() {
    final json = _prefs.getString('alarms');
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((a) => DeviceAlarm.fromJson(a as Map<String, dynamic>)).toList()
      ..sort((a, b) => a.time.totalMinutes.compareTo(b.time.totalMinutes));
  }

  Future<void> saveAlarm(DeviceAlarm alarm) async {
    final alarms = getAlarms();
    final idx = alarms.indexWhere((a) => a.id == alarm.id);
    if (idx >= 0) {
      alarms[idx] = alarm;
    } else {
      alarms.add(alarm);
    }
    await _prefs.setString(
      'alarms',
      jsonEncode(alarms.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> deleteAlarm(String id) async {
    final alarms = getAlarms()..removeWhere((a) => a.id == id);
    await _prefs.setString(
      'alarms',
      jsonEncode(alarms.map((a) => a.toJson()).toList()),
    );
  }
}
