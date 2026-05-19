import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/openclaw_node_service.dart';
import '../services/calendar_service.dart';
import '../services/alarm_service.dart';
import '../models/calendar_event.dart';
import '../widgets/connection_status.dart';

/// Full calendar screen with month view + event list.
class CalendarScreen extends StatefulWidget {
  final OpenClawNodeService nodeService;
  final CalendarService calendarService;
  final AlarmService alarmService;

  const CalendarScreen({
    super.key,
    required this.nodeService,
    required this.calendarService,
    required this.alarmService,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _selectedDate = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eventsForDay = widget.calendarService.eventsForDate(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          ConnectionDot(service: widget.nodeService),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Calendar
          Card(
            margin: const EdgeInsets.all(8),
            child: TableCalendar(
              firstDay: DateTime(2020),
              lastDay: DateTime(2030),
              focusedDay: _selectedDate,
              selectedDayPredicate: (day) => isSameDay(_selectedDate, day),
              calendarFormat: _calendarFormat,
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              onDaySelected: (selectedDay, focusedDay) {
                setState(() => _selectedDate = selectedDay);
              },
              eventLoader: (day) =>
                  widget.calendarService.eventsForDate(day).length > 0
                      ? [true]
                      : [],
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
              ),
            ),
          ),

          // Day header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text(
                  DateFormat('EEEE, MMMM d').format(_selectedDate),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${eventsForDay.length} event${eventsForDay.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),

          // Event list
          Expanded(
            child: eventsForDay.isEmpty
                ? Center(
                    child: Text(
                      'No events on this day',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: eventsForDay.length,
                    itemBuilder: (_, i) =>
                        _buildEventTile(context, eventsForDay[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEventDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEventTile(BuildContext context, CalendarEvent event) {
    final timeStr =
        '${DateFormat('HH:mm').format(event.startTime)} - ${DateFormat('HH:mm').format(event.endTime)}';
    return Dismissible(
      key: Key(event.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => widget.calendarService.removeEvent(event.id),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          leading: Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          title: Text(event.title,
              style: const TextStyle(fontWeight: FontWeight.w500)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(timeStr),
              if (event.description != null && event.description!.isNotEmpty)
                Text(event.description!,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
            ],
          ),
          trailing: PopupMenuButton(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
            onSelected: (v) {
              if (v == 'delete') widget.calendarService.removeEvent(event.id);
              if (v == 'edit') _showEditEventDialog(context, event);
            },
          ),
        ),
      ),
    );
  }

  // ── Add / Edit Dialogs ────────────────────────────────────────────

  void _showAddEventDialog(BuildContext context) {
    _showEventDialog(context, event: null);
  }

  void _showEditEventDialog(BuildContext context, CalendarEvent event) {
    _showEventDialog(context, event: event);
  }

  void _showEventDialog(BuildContext context, {CalendarEvent? event}) {
    final titleCtl = TextEditingController(text: event?.title ?? '');
    final descCtl = TextEditingController(text: event?.description ?? '');
    final locCtl = TextEditingController(text: event?.location ?? '');
    DateTime startDate = event?.startTime ?? DateTime.now();
    DateTime endDate = event?.endTime ?? DateTime.now().add(const Duration(hours: 1));
    bool allDay = event?.allDay ?? false;

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
                Text(event == null ? 'Add Event' : 'Edit Event',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(
                    controller: titleCtl,
                    decoration: const InputDecoration(
                        labelText: 'Title', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                TextField(
                    controller: descCtl,
                    decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder()),
                    maxLines: 2),
                const SizedBox(height: 8),
                TextField(
                    controller: locCtl,
                    decoration: const InputDecoration(
                        labelText: 'Location',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _dateTimePicker(ctx, 'Start', startDate, (d) {
                        setModalState(() => startDate = d);
                        if (endDate.isBefore(startDate)) {
                          endDate = startDate.add(const Duration(hours: 1));
                        }
                      }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _dateTimePicker(ctx, 'End', endDate, (d) {
                        setModalState(() => endDate = d);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('All Day'),
                    Switch(
                      value: allDay,
                      onChanged: (v) => setModalState(() => allDay = v),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (titleCtl.text.trim().isEmpty) return;
                      final updated = (event ?? CalendarEvent(
                        id: '',
                        title: '',
                        startTime: startDate,
                        endTime: endDate,
                      )).copyWith(
                        title: titleCtl.text.trim(),
                        description: descCtl.text.trim().isEmpty
                            ? null
                            : descCtl.text.trim(),
                        location: locCtl.text.trim().isEmpty
                            ? null
                            : locCtl.text.trim(),
                        startTime: startDate,
                        endTime: allDay
                            ? startDate.add(const Duration(days: 1))
                            : endDate,
                        allDay: allDay,
                      );

                      if (event == null) {
                        await widget.calendarService.addEvent(
                          title: updated.title,
                          startTime: updated.startTime,
                          endTime: updated.endTime,
                          description: updated.description,
                          location: updated.location,
                          allDay: updated.allDay,
                        );
                      } else {
                        await widget.calendarService.updateEvent(updated);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: Text(event == null ? 'Add Event' : 'Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dateTimePicker(BuildContext ctx, String label, DateTime value,
      ValueChanged<DateTime> onChanged) {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: ctx,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (date == null) return;
        final time = await showTimePicker(
          context: ctx,
          initialTime: TimeOfDay.fromDateTime(value),
        );
        if (time == null) return;
        onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(DateFormat('MM/dd HH:mm').format(value)),
      ),
    );
  }
}
