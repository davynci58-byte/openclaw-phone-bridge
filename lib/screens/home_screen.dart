import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/openclaw_node_service.dart';
import '../services/calendar_service.dart';
import '../services/alarm_service.dart';
import '../widgets/connection_status.dart';
import 'calendar_screen.dart';
import 'alarm_screen.dart';
import 'settings_screen.dart';

/// Main dashboard showing an overview of upcoming events and alarms.
class HomeScreen extends StatefulWidget {
  final OpenClawNodeService nodeService;
  final CalendarService calendarService;
  final AlarmService alarmService;

  const HomeScreen({
    super.key,
    required this.nodeService,
    required this.calendarService,
    required this.alarmService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {



  @override
  void initState() {
    super.initState();
    widget.calendarService.addListener(_onDataChanged);
    widget.alarmService.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    widget.calendarService.removeListener(_onDataChanged);
    widget.alarmService.removeListener(_onDataChanged);
    super.dispose();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          // Top bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.shield, size: 28),
                  const SizedBox(width: 8),
                  Text('OpenClaw Bridge',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
                  const Spacer(),
                  ConnectionDot(service: widget.nodeService),
                ],
              ),
            ),
          ),
          ConnectionStatusBar(service: widget.nodeService),

          // Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                // Force UI refresh
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSummaryCards(context),
                  const SizedBox(height: 24),
                  _buildSection(
                    context,
                    title: 'Upcoming Events',
                    icon: Icons.calendar_today,
                    child: _buildUpcomingEvents(context),
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    context,
                    title: 'Active Alarms',
                    icon: Icons.alarm,
                    child: _buildAlarmList(context),
                  ),
                ],
              ),
            ),
          ),

          // Bottom nav
          _buildBottomNav(context),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    final theme = Theme.of(context);
    final upcomingEvents = widget.calendarService.upcomingEvents(24);
    final activeAlarms = widget.alarmService.alarms.where((a) => a.enabled).length;

    return Row(
      children: [
        Expanded(
          child: _card(
            theme,
            icon: Icons.calendar_month,
            label: 'Today',
            value: widget.calendarService.eventsForDate(DateTime.now()).length.toString(),
            color: Colors.blue,
            onTap: () => _navigateTo(context, CalendarScreen(
              nodeService: widget.nodeService,
              calendarService: widget.calendarService,
              alarmService: widget.alarmService,
            )),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _card(
            theme,
            icon: Icons.alarm,
            label: 'Alarms',
            value: '$activeAlarms active',
            color: Colors.orange,
            onTap: () => _navigateTo(context, AlarmScreen(
              nodeService: widget.nodeService,
              calendarService: widget.calendarService,
              alarmService: widget.alarmService,
            )),
          ),
        ),
      ],
    );
  }

  Widget _card(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey)),
              const SizedBox(height: 4),
              Text(value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildUpcomingEvents(BuildContext context) {
    final events = widget.calendarService.upcomingEvents(48);
    if (events.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No upcoming events.\nOpenClaw can add events for you!',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Column(
      children: events.take(5).map((event) {
        final timeStr = DateFormat('EEE, MMM d · HH:mm').format(event.startTime);
        return Card(
          child: ListTile(
            leading: const Icon(Icons.event, color: Colors.blue),
            title: Text(event.title, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(timeStr),
            trailing: event.description != null
                ? Icon(Icons.description_outlined, size: 18, color: Colors.grey[400])
                : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAlarmList(BuildContext context) {
    final enabled = widget.alarmService.alarms.where((a) => a.enabled).toList();
    if (enabled.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No active alarms.\nOpenClaw can set alarms for you!',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    return Column(
      children: enabled.take(5).map((alarm) {
        return Card(
          child: ListTile(
            leading: const Icon(Icons.alarm, color: Colors.orange),
            title: Text(alarm.label),
            subtitle: Text(alarm.timeFormatted),
            trailing: Text(alarm.repeatSummary, style: const TextStyle(fontSize: 12)),
          ),
        );
      }).toList(),
    );
  }

  void _navigateTo(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.2))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navItem(Icons.home, 'Home', true, () {}),
              _navItem(Icons.calendar_month, 'Calendar', false, () {
                _navigateTo(context, CalendarScreen(
                  nodeService: widget.nodeService,
                  calendarService: widget.calendarService,
                  alarmService: widget.alarmService,
                ));
              }),
              _navItem(Icons.alarm, 'Alarms', false, () {
                _navigateTo(context, AlarmScreen(
                  nodeService: widget.nodeService,
                  calendarService: widget.calendarService,
                  alarmService: widget.alarmService,
                ));
              }),
              _navItem(Icons.settings, 'Settings', false, () {
                _navigateTo(context, SettingsScreen(
                  nodeService: widget.nodeService,
                ));
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: active ? Colors.blue : Colors.grey),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: active ? Colors.blue : Colors.grey)),
          ],
        ),
      ),
    );
  }
}
