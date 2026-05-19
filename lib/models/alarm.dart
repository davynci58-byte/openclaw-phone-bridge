/// An alarm model — local device alarm managed by OpenClaw.
class DeviceAlarm {
  final String id;
  final String label;
  final TimeOfDay time;
  final List<bool> repeatDays; // Sun..Sat, 7 bools
  final bool enabled;
  final String? sound;
  final int? snoozeMinutes;

  DeviceAlarm({
    required this.id,
    required this.label,
    required this.time,
    this.repeatDays = const [false, false, false, false, false, false, false],
    this.enabled = true,
    this.sound,
    this.snoozeMinutes = 5,
  });

  DeviceAlarm copyWith({
    String? id,
    String? label,
    TimeOfDay? time,
    List<bool>? repeatDays,
    bool? enabled,
    String? sound,
    int? snoozeMinutes,
  }) {
    return DeviceAlarm(
      id: id ?? this.id,
      label: label ?? this.label,
      time: time ?? this.time,
      repeatDays: repeatDays ?? this.repeatDays,
      enabled: enabled ?? this.enabled,
      sound: sound ?? this.sound,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
    );
  }

  String get timeFormatted {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String get repeatSummary {
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final active = <String>[];
    for (var i = 0; i < 7; i++) {
      if (repeatDays[i]) active.add(days[i]);
    }
    return active.isEmpty ? 'Once' : active.join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hour': time.hour,
        'minute': time.minute,
        'repeatDays': repeatDays,
        'enabled': enabled,
        'sound': sound,
        'snoozeMinutes': snoozeMinutes,
      };

  factory DeviceAlarm.fromJson(Map<String, dynamic> json) => DeviceAlarm(
        id: json['id'] as String,
        label: json['label'] as String? ?? 'Alarm',
        time: TimeOfDay(
          hour: json['hour'] as int,
          minute: json['minute'] as int,
        ),
        repeatDays: (json['repeatDays'] as List<dynamic>?)
                ?.map((e) => e as bool)
                .toList() ??
            List.filled(7, false),
        enabled: json['enabled'] as bool? ?? true,
        sound: json['sound'] as String?,
        snoozeMinutes: json['snoozeMinutes'] as int? ?? 5,
      );

  @override
  String toString() => 'DeviceAlarm($label @ $timeFormatted)';
}

/// Simplified time-of-day value (not Flutter's, serialisable).
class TimeOfDay {
  final int hour;
  final int minute;

  const TimeOfDay({required this.hour, required this.minute});

  int get totalMinutes => hour * 60 + minute;

  DateTime nextOccurrence(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  @override
  bool operator ==(Object other) =>
      other is TimeOfDay && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);
}
