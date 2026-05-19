import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/alarm.dart';
import 'services/storage_service.dart';
import 'services/openclaw_node_service.dart';
import 'services/calendar_service.dart';
import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';

/// Root entry point.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);

  final calendarService = CalendarService(storage: storage);
  await calendarService.init();

  final alarmService = AlarmService(storage: storage);
  await alarmService.init();

  final notifService = NotificationService();
  await notifService.init();

  // OpenClaw node service
  final nodeService = OpenClawNodeService(
    prefs: prefs,
    onInvoke: (command, args) => _handleInvoke(
      command, args, calendarService, alarmService, notifService,
    ),
  );

  // Wire alarm events → OpenClaw
  alarmService.onAlarmFired = (alarm) {
    nodeService.sendNodeEvent('alarm.fired', {
      'id': alarm.id,
      'label': alarm.label,
      'time': alarm.timeFormatted,
      'triggeredAt': DateTime.now().toIso8601String(),
    });
  };

  // Connect after a short delay
  Future.delayed(const Duration(seconds: 1), () => nodeService.start());

  runApp(OpenClawBridgeApp(
    nodeService: nodeService,
    calendarService: calendarService,
    alarmService: alarmService,
  ));
}

/// Route incoming OpenClaw invoke commands.
Future<Map<String, dynamic>> _handleInvoke(
  String command,
  Map<String, dynamic> args,
  CalendarService calendarService,
  AlarmService alarmService,
  NotificationService notifService,
) async {
  debugPrint('⚡ Invoke: $command $args');

  switch (command) {
    case 'calendar.list':
      return {'count': calendarService.events.length, 'events': calendarService.events.map((e) => e.toJson()).toList()};

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
      final cid = args['id'] as String?;
      if (cid == null) return {'success': false, 'error': 'Missing id'};
      await calendarService.removeEvent(cid);
      return {'success': true};

    case 'calendar.upcoming':
      final hours = args['hours'] as int? ?? 24;
      final evts = calendarService.upcomingEvents(hours);
      return {'count': evts.length, 'events': evts.map((e) => e.toJson()).toList()};

    case 'alarm.list':
      return {'count': alarmService.alarms.length, 'alarms': alarmService.alarms.map((a) => a.toJson()).toList()};

    case 'alarm.set':
      final alarm = await alarmService.addAlarm(
        label: args['label'] as String? ?? 'Alarm',
        time: AlarmTime(hour: args['hour'] as int? ?? 7, minute: args['minute'] as int? ?? 0),
        repeatDays: (args['repeatDays'] as List<dynamic>?)?.map((e) => e as bool).toList(),
        snoozeMinutes: args['snoozeMinutes'] as int? ?? 5,
      );
      return {'id': alarm.id, 'time': alarm.timeFormatted, 'success': true};

    case 'alarm.clear':
      final aid = args['id'] as String?;
      if (aid == null) {
        for (final a in alarmService.alarms.toList()) await alarmService.removeAlarm(a.id);
        return {'cleared': 'all', 'success': true};
      }
      await alarmService.removeAlarm(aid);
      return {'cleared': aid, 'success': true};

    case 'alarm.toggle':
      final aid2 = args['id'] as String?;
      if (aid2 == null) return {'success': false, 'error': 'Missing id'};
      await alarmService.toggleAlarm(aid2);
      return {'success': true};

    case 'notification.send':
      await notifService.showNotification(
        title: args['title'] as String? ?? 'OpenClaw',
        body: args['body'] as String? ?? '',
        payload: args['payload'] as String?,
        playSound: args['playSound'] as bool? ?? true,
      );
      return {'success': true};

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



// ── App ─────────────────────────────────────────────────────────────

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
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1E88E5),
        brightness: Brightness.dark,
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
