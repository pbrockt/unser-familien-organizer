import '../../core/notifications/notification_service.dart';
import '../calendar/calendar_event.dart';
import '../tasks/task_item.dart';
import '../weather/weather_service.dart';

/// Feste Notification-ID des täglichen Briefings (außerhalb der Erinnerungs-IDs).
const int kBriefingNotificationId = 900001;

/// Plant das tägliche Morgen-Briefing als eine [ScheduledReminder] zum nächsten
/// Briefing-Zeitpunkt (heute, sonst morgen). `null`, wenn deaktiviert.
ScheduledReminder? planDailyBriefing({
  required List<CalendarEvent> events,
  required List<TaskList> taskLists,
  Map<String, DayWeather> weather = const {},
  required bool enabled,
  required int minutesOfDay,
  DateTime? now,
}) {
  if (!enabled) return null;
  final n = now ?? DateTime.now();
  var when = DateTime(
    n.year,
    n.month,
    n.day,
    minutesOfDay ~/ 60,
    minutesOfDay % 60,
  );
  if (!when.isAfter(n)) when = when.add(const Duration(days: 1));
  final day = DateTime(when.year, when.month, when.day);

  final eventCount = events.where((e) => e.occursOn(day)).length;
  final taskCount = taskLists
      .expand((l) => l.items)
      .where(
        (t) =>
            !t.completed &&
            t.due != null &&
            !DateTime(t.due!.year, t.due!.month, t.due!.day).isAfter(day),
      )
      .length;

  final parts = <String>[
    eventCount == 0
        ? 'Keine Termine'
        : eventCount == 1
        ? '1 Termin'
        : '$eventCount Termine',
  ];
  if (taskCount > 0) {
    parts.add(
      taskCount == 1 ? '1 fällige Aufgabe' : '$taskCount fällige Aufgaben',
    );
  }
  String two(int v) => v.toString().padLeft(2, '0');
  final key = '${day.year}-${two(day.month)}-${two(day.day)}';
  final w = weather[key];
  if (w != null) {
    parts.add(
      '${weatherEmoji(w.code)} ${w.tempMax.round()}°/${w.tempMin.round()}°',
    );
  }

  final isToday = day == DateTime(n.year, n.month, n.day);
  return ScheduledReminder(
    id: kBriefingNotificationId,
    title: isToday ? 'Guten Morgen! ☀️' : 'Vorschau für morgen',
    body: parts.join(' · '),
    when: when,
  );
}
