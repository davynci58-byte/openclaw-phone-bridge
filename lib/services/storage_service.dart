import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/calendar_event.dart';
import '../models/alarm.dart';

/// Persists device identity, calendar events, and alarms locally.
class StorageService {
  static const _keyDeviceId = 'device_id';
  static const _keyPrivateKey = 'device_private_key';
  static const _keyDeviceToken = 'device_token';
  static const _keyPubKey = 'device_public_key';
  static const _prefsCalPrefix = 'cal_event_';
  static const _prefsAlarmPrefix = 'alarm_';
  static const _prefsCalIndex = 'cal_event_ids';
  static const _prefsAlarmIndex = 'alarm_ids';
  static const _keyLastConnectUri = 'last_connect_uri';

  late SharedPreferences _prefs;
  final _uuid = const Uuid();

  // ── Init ──────────────────────────────────────────────────────────

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── Device Identity ───────────────────────────────────────────────

  String get deviceId => _prefs.getString(_keyDeviceId) ?? _initDeviceId();
  String get rawIdentityKeyHex => _prefs.getString(_keyPrivateKey) ?? '';
  String get rawPublicKeyHex => _prefs.getString(_keyPubKey) ?? '';

  String _initDeviceId() {
    final id = _uuid.v4();
    unawaited(_prefs.setString(_keyDeviceId, id));
    return id;
  }

  Future<void> storeKeypair(String privateKeyHex, String publicKeyHex) async {
    await _prefs.setString(_keyPrivateKey, privateKeyHex);
    await _prefs.setString(_keyPubKey, publicKeyHex);
  }

  String? get deviceToken => _prefs.getString(_keyDeviceToken);
  Future<void> setDeviceToken(String? token) async {
    if (token == null) {
      await _prefs.remove(_keyDeviceToken);
    } else {
      await _prefs.setString(_keyDeviceToken, token);
    }
  }

  String? get lastConnectUri => _prefs.getString(_keyLastConnectUri);
  Future<void> setLastConnectUri(String uri) async {
    await _prefs.setString(_keyLastConnectUri, uri);
  }

  // ── Calendar Events ───────────────────────────────────────────────

  List<CalendarEvent> getCalendarEvents() {
    final ids = _prefs.getStringList(_prefsCalIndex) ?? [];
    return ids.map((id) {
      final json = _prefs.getString('$_prefsCalPrefix$id');
      if (json == null) return null;
      return CalendarEvent.fromJson(jsonDecode(json));
    }).whereType<CalendarEvent>().toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<void> saveCalendarEvent(CalendarEvent event) async {
    final ids = _prefs.getStringList(_prefsCalIndex) ?? [];
    if (!ids.contains(event.id)) {
      ids.add(event.id);
      await _prefs.setStringList(_prefsCalIndex, ids);
    }
    await _prefs.setString(
      '$_prefsCalPrefix${event.id}',
      jsonEncode(event.toJson()),
    );
  }

  Future<void> deleteCalendarEvent(String id) async {
    final ids = _prefs.getStringList(_prefsCalIndex) ?? [];
    ids.remove(id);
    await _prefs.setStringList(_prefsCalIndex, ids);
    await _prefs.remove('$_prefsCalPrefix$id');
  }

  // ── Alarms ────────────────────────────────────────────────────────

  List<DeviceAlarm> getAlarms() {
    final ids = _prefs.getStringList(_prefsAlarmIndex) ?? [];
    return ids.map((id) {
      final json = _prefs.getString('$_prefsAlarmPrefix$id');
      if (json == null) return null;
      return DeviceAlarm.fromJson(jsonDecode(json));
    }).whereType<DeviceAlarm>().toList()
      ..sort((a, b) => a.time.totalMinutes.compareTo(b.time.totalMinutes));
  }

  Future<void> saveAlarm(DeviceAlarm alarm) async {
    final ids = _prefs.getStringList(_prefsAlarmIndex) ?? [];
    if (!ids.contains(alarm.id)) {
      ids.add(alarm.id);
      await _prefs.setStringList(_prefsAlarmIndex, ids);
    }
    await _prefs.setString(
      '$_prefsAlarmPrefix${alarm.id}',
      jsonEncode(alarm.toJson()),
    );
  }

  Future<void> deleteAlarm(String id) async {
    final ids = _prefs.getStringList(_prefsAlarmIndex) ?? [];
    ids.remove(id);
    await _prefs.setStringList(_prefsAlarmIndex, ids);
    await _prefs.remove('$_prefsAlarmPrefix$id');
  }
}
