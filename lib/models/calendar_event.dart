/// A calendar event model, local + serialisable for OpenClaw.
class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final String? location;
  final DateTime startTime;
  final DateTime endTime;
  final bool allDay;
  final int? reminderMinutes; // minutes before event to remind

  CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.startTime,
    required this.endTime,
    this.allDay = false,
    this.reminderMinutes,
  });

  CalendarEvent copyWith({
    String? id,
    String? title,
    String? description,
    String? location,
    DateTime? startTime,
    DateTime? endTime,
    bool? allDay,
    int? reminderMinutes,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      allDay: allDay ?? this.allDay,
      reminderMinutes: reminderMinutes ?? this.reminderMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'location': location,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'allDay': allDay,
        'reminderMinutes': reminderMinutes,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        location: json['location'] as String?,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        allDay: json['allDay'] as bool? ?? false,
        reminderMinutes: json['reminderMinutes'] as int?,
      );

  @override
  String toString() => 'CalendarEvent($title @ $startTime)';
}
