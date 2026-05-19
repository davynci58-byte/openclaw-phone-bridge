import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/calendar_event.dart';
import 'storage_service.dart';

/// Manages calendar events locally + syncs to native calendar if permitted.
class CalendarService extends ChangeNotifier {
  final StorageService _storage;
  final _uuid = const Uuid();

  List<CalendarEvent> _events = [];

  List<CalendarEvent> get events => List.unmodifiable(_events);

  CalendarService({required StorageService storage}) : _storage = storage;

  // ── Init ──────────────────────────────────────────────────────────

  Future<void> init() async {
    _events = _storage.getCalendarEvents();
    notifyListeners();
    // In production: also sync with native device_calendar here
  }

  // ── CRUD ──────────────────────────────────────────────────────────

  Future<CalendarEvent> addEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
    String? location,
    bool allDay = false,
    int? reminderMinutes,
  }) async {
    final event = CalendarEvent(
      id: _uuid.v4(),
      title: title,
      description: description,
      location: location,
      startTime: startTime,
      endTime: endTime,
      allDay: allDay,
      reminderMinutes: reminderMinutes,
    );
    await _storage.saveCalendarEvent(event);
    _events.add(event);
    _events.sort((a, b) => a.startTime.compareTo(b.startTime));
    notifyListeners();
    return event;
  }

  Future<CalendarEvent> updateEvent(CalendarEvent event) async {
    await _storage.saveCalendarEvent(event);
    final idx = _events.indexWhere((e) => e.id == event.id);
    if (idx >= 0) {
      _events[idx] = event;
    } else {
      _events.add(event);
    }
    _events.sort((a, b) => a.startTime.compareTo(b.startTime));
    notifyListeners();
    return event;
  }

  Future<void> removeEvent(String id) async {
    await _storage.deleteCalendarEvent(id);
    _events.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  CalendarEvent? getEvent(String id) {
    try {
      return _events.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get events for a specific date.
  List<CalendarEvent> eventsForDate(DateTime date) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final dayEnd = dayStart.add(const Duration(hours: 24));
    return _events
        .where((e) => e.startTime.isAfter(dayStart.subtract(const Duration(seconds: 1)))
            && e.startTime.isBefore(dayEnd))
        .toList();
  }

  /// Get upcoming events within [hours] from now.
  List<CalendarEvent> upcomingEvents(int hours) {
    final now = DateTime.now();
    final until = now.add(Duration(hours: hours));
    return _events
        .where((e) => e.startTime.isAfter(now) && e.startTime.isBefore(until))
        .toList();
  }
}
