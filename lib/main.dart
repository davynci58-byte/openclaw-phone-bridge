import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'services/openclaw_node_service.dart';
import 'services/calendar_service.dart';
import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'models/alarm.dart' as alarm_model;

/// Root entry point — initialises all services and connects to OpenClaw.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Init Services ──────────────────────────────────────────────────
  final storage = StorageService();
  await storage.init();

  final calendarService = CalendarService(storage: storage);
  await calendarService.init();

  final alarmService = AlarmService(storage: storage);
  await alarmService.init();

  final notifService = NotificationService();
  await notifService.init();

  // ── Init OpenClaw Node Service ─────────────────────────────────────
  final nodeService = OpenClawNodeService(
    storage: storage,
    onInvoke: (command, args) => _handleInvoke(
      command, args, calendarService, alarmService, notifService,
    ),
  );

  // Wire alarm firings to OpenClaw events
  alarmService.onAlarmFired = (alarm) {
    nodeService.sendNodeEvent('alarm.fired', {
      'id': alarm.id,
      'label': alarm.label,
      'time': alarm.timeFormatted,
      'triggeredAt': DateTime.now().toIso8601String(),
    });
  };

  // ── Connect ────────────────────────────────────────────────────────
  // Small delay to let the UI settle, then connect
  Future.delayed(const Duration(seconds: 1), () {
    nodeService.start();
  });

  // ── Run App ────────────────────────────────────────────────────────
  runApp(OpenClawBridgeApp(
    nodeService: nodeService,
    calendarService: calendarService,
    alarmService: alarmService,
  ));
}

/// Route incoming invoke commands from OpenClaw to the right service.
Future<Map<String, dynamic>> _handleInvoke(
  String command,
  Map<String, dynamic> args,
  CalendarService calendarService,
  AlarmService alarmService,
  NotificationService notifService,
) async {
  debugPrint('⚡ Invoke: $command $args');

  switch (command) {
    // ── Calendar ───────────────────────────────────────────────────
    case 'calendar.list':
      final events = calendarService.events;
      return {
        'count': events.length,
        'events': events.map((e) => e.toJson()).toList(),
      };

    case 'calendar.add':
      final event = await calendarService.addEvent(
        title: args['title'] as String? ?? 'Event',
        description: args['description'] as String?,
        location: args['location'] as String?,
        startTime: DateTime.parse(args['startTime'] as String),
        endTime: DateTime.parse(args['endTime'] as String),
        allDay: args['allDay'] as bool? ?? false,
        reminderMinutes: args['reminderMinutes'] as int?,
      );
      return {'id': event.id, 'success': true};

    case 'calendar.remove':
      final id = args['id'] as String?;
      if (id == null) return {'success': false, 'error': 'Missing event id'};
      await calendarService.removeEvent(id);
      return {'success': true};

    case 'calendar.upcoming':
      final hours = args['hours'] as int? ?? 24;
      final events = calendarService.upcomingEvents(hours);
      return {
        'count': events.length,
        'events': events.map((e) => e.toJson()).toList(),
      };

    // ── Alarms ─────────────────────────────────────────────────────
    case 'alarm.list':
      return {
        'count': alarmService.alarms.length,
        'alarms': alarmService.alarms.map((a) => a.toJson()).toList(),
      };

    case 'alarm.set':
      final hour = args['hour'] as int? ?? 7;
      final minute = args['minute'] as int? ?? 0;
      final label = args['label'] as String? ?? 'Alarm';
      final repeatDays = (args['repeatDays'] as List<dynamic>?)
          ?.map((e) => e as bool)
          .toList();
      final snoozeMin = args['snoozeMinutes'] as int? ?? 5;

      final alarm = await alarmService.addAlarm(
        label: label,
        time: alarm_model.TimeOfDay(hour: hour, minute: minute),
        repeatDays: repeatDays,
        snoozeMinutes: snoozeMin,
      );
      return {'id': alarm.id, 'time': alarm.timeFormatted, 'success': true};

    case 'alarm.clear':
      final id = args['id'] as String?;
      if (id == null) {
        // Clear all alarms
        for (final a in alarmService.alarms.toList()) {
          await alarmService.removeAlarm(a.id);
        }
        return {'cleared': 'all', 'success': true};
      }
      await alarmService.removeAlarm(id);
      return {'cleared': id, 'success': true};

    case 'alarm.toggle':
      final id = args['id'] as String?;
      if (id == null) return {'success': false, 'error': 'Missing alarm id'};
      await alarmService.toggleAlarm(id);
      return {'success': true};

    // ── Notifications ──────────────────────────────────────────────
    case 'notification.send':
      await notifService.showNotification(
        title: args['title'] as String? ?? 'OpenClaw',
        body: args['body'] as String? ?? '',
        payload: args['payload'] as String?,
        playSound: args['playSound'] as bool? ?? true,
      );
      return {'success': true};

    // ── Health ─────────────────────────────────────────────────────
    case 'phone.ping':
      return {
        'deviceId': 'flutter-phone',
        'timestamp': DateTime.now().toIso8601String(),
        'platform': 'android',
        'appVersion': '1.0.0',
        'alarms': alarmService.alarms.length,
        'events': calendarService.events.length,
      };

    default:
      throw Exception('Unknown command: $command');
  }
}



// ── App Widget ─────────────────────────────────────────────────────────

class OpenClawBridgeApp extends StatelessWidget {
  final OpenClawNodeService nodeService;
  final CalendarService calendarService;
  final AlarmService alarmService;

  const OpenClawBridgeApp({
    super.key,
    required this.nodeService,
    required this.calendarService,
    required this.alarmService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenClaw Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E88E5),
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E88E5),
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(centerTitle: true),
      ),
      themeMode: ThemeMode.system,
      home: HomeScreen(
        nodeService: nodeService,
        calendarService: calendarService,
        alarmService: alarmService,
      ),
    );
  }
}
