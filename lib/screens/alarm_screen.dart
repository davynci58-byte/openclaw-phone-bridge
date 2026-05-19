import 'package:flutter/material.dart';
import '../services/openclaw_node_service.dart';
import '../services/calendar_service.dart';
import '../services/alarm_service.dart';
import '../models/alarm.dart';
import '../widgets/connection_status.dart';

/// Alarm management screen.
class AlarmScreen extends StatefulWidget {
  final OpenClawNodeService nodeService;
  final CalendarService calendarService;
  final AlarmService alarmService;

  const AlarmScreen({
    super.key,
    required this.nodeService,
    required this.calendarService,
    required this.alarmService,
  });

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  @override
  void initState() {
    super.initState();
    widget.alarmService.addListener(_onAlarmsChanged);
  }

  @override
  void dispose() {
    widget.alarmService.removeListener(_onAlarmsChanged);
    super.dispose();
  }

  void _onAlarmsChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final alarms = widget.alarmService.alarms;
    final enabled =
        alarms.where((a) => a.enabled).length;
    final disabled =
        alarms.where((a) => !a.enabled).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarms'),
        actions: [
          ConnectionDot(service: widget.nodeService),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Summary
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _statCard(context, Icons.alarm_on, 'Active', enabled.toString(),
                    Colors.green),
                const SizedBox(width: 12),
                _statCard(context, Icons.alarm_off, 'Disabled',
                    disabled.toString(), Colors.grey),
                const SizedBox(width: 12),
                _statCard(context, Icons.notifications, 'Total',
                    alarms.length.toString(), Colors.blue),
              ],
            ),
          ),

          // Alarm list
          Expanded(
            child: alarms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.alarm_add, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No alarms yet',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'OpenClaw can set alarms for you,\nor tap + to add one',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: alarms.length,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemBuilder: (_, i) => _buildAlarmTile(context, alarms[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAlarmDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _statCard(BuildContext context, IconData icon, String label,
      String value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 4),
              Text(value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlarmTile(BuildContext context, DeviceAlarm alarm) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Opacity(
        opacity: alarm.enabled ? 1.0 : 0.5,
        child: ListTile(
          leading: Icon(
            alarm.enabled ? Icons.alarm : Icons.alarm_off,
            color: alarm.enabled ? Colors.orange : Colors.grey,
          ),
          title: Row(
            children: [
              Text(
                alarm.timeFormatted,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(alarm.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14)),
              ),
            ],
          ),
          subtitle: Text(alarm.repeatSummary,
              style: const TextStyle(fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: alarm.enabled,
                onChanged: (_) => widget.alarmService.toggleAlarm(alarm.id),
              ),
              PopupMenuButton(
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (v) {
                  if (v == 'delete') widget.alarmService.removeAlarm(alarm.id);
                  if (v == 'edit') _showEditAlarmDialog(context, alarm);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Add / Edit Dialogs ────────────────────────────────────────────

  void _showAddAlarmDialog(BuildContext context) {
    _showAlarmDialog(context, alarm: null);
  }

  void _showEditAlarmDialog(BuildContext context, DeviceAlarm alarm) {
    _showAlarmDialog(context, alarm: alarm);
  }

  void _showAlarmDialog(BuildContext context, {DeviceAlarm? alarm}) {
    int hour = alarm?.time.hour ?? 7;
    int minute = alarm?.time.minute ?? 0;
    final labelCtl =
        TextEditingController(text: alarm?.label ?? 'Wake up');
    List<bool> repeatDays =
        alarm?.repeatDays ?? List.filled(7, false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) => Padding(
            padding: EdgeInsets.fromLTRB(
              16, 16, 16,
              MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    alarm == null ? 'New Alarm' : 'Edit Alarm',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 16),

                // Label
                TextField(
                  controller: labelCtl,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Time picker
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        hour.toString().padLeft(2, '0'),
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Text(':', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                    SizedBox(
                      width: 80,
                      child: Text(
                        minute.toString().padLeft(2, '0'),
                        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.access_time),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay(hour: hour, minute: minute),
                        );
                        if (picked != null) {
                          setModalState(() {
                            hour = picked.hour;
                            minute = picked.minute;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Repeat days
                const Text('Repeat', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: List.generate(7, (i) {
                    const dayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
                    return FilterChip(
                      label: Text(dayLabels[i], style: const TextStyle(fontSize: 12)),
                      selected: repeatDays[i],
                      onSelected: (v) =>
                          setModalState(() => repeatDays[i] = v),
                    );
                  }),
                ),
                const SizedBox(height: 16),

                // Save button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final newAlarm = DeviceAlarm(
                        id: alarm?.id ?? '',
                        label: labelCtl.text.trim().isEmpty
                            ? 'Alarm'
                            : labelCtl.text.trim(),
                        time: AlarmTime(hour: hour, minute: minute),
                        repeatDays: repeatDays,
                        snoozeMinutes: alarm?.snoozeMinutes ?? 5,
                      );
                      if (alarm == null) {
                        await widget.alarmService.addAlarm(
                          label: newAlarm.label,
                          time: newAlarm.time,
                          repeatDays: newAlarm.repeatDays,
                        );
                      } else {
                        await widget.alarmService.updateAlarm(newAlarm);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(alarm == null ? 'Add Alarm' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
