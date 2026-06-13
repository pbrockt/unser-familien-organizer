import 'package:intl/intl.dart';

import '../../core/notifications/notification_service.dart';
import '../calendar/calendar_event.dart';
import '../tasks/task_item.dart';

/// Erstellt die zu planenden Erinnerungen aus Terminen und Aufgaben.
///
/// - Termine: [leadMinutes] vor Beginn (keine Ganztags-Termine).
/// - Aufgaben mit Fälligkeit: zur Fälligkeitszeit bzw. um 9 Uhr am Fälligkeitstag.
///
/// Reine Funktion ohne Riverpod – nutzbar in der UI und im Hintergrund.
List<ScheduledReminder> planReminders({
  required List<CalendarEvent> events,
  required List<TaskList> taskLists,
  required int leadMinutes,
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  final horizon = n.add(const Duration(days: 14));
  final reminders = <ScheduledReminder>[];

  // Termine.
  final lead = Duration(minutes: leadMinutes);
  final upcoming = events
      .where((e) =>
          !e.allDay && e.start.isAfter(n) && e.start.isBefore(horizon))
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  var id = 1;
  for (final e in upcoming) {
    final when = e.start.subtract(lead);
    if (!when.isAfter(n)) continue;
    final location =
        (e.location != null && e.location!.isNotEmpty) ? ' · ${e.location}' : '';
    reminders.add(ScheduledReminder(
      id: id++,
      title: e.summary,
      body: 'Beginnt um ${DateFormat('HH:mm').format(e.start)} Uhr$location',
      when: when,
    ));
    if (id > 60) break;
  }

  // Aufgaben mit Fälligkeit.
  var taskId = 1000;
  for (final list in taskLists) {
    for (final t in list.items) {
      if (t.completed || t.due == null) continue;
      final due = t.due!;
      final midnight = due.hour == 0 && due.minute == 0 && due.second == 0;
      final when =
          midnight ? DateTime(due.year, due.month, due.day, 9) : due;
      if (!when.isAfter(n) || when.isAfter(horizon)) continue;
      reminders.add(ScheduledReminder(
        id: taskId++,
        title: 'Aufgabe fällig',
        body: t.summary,
        when: when,
      ));
      if (taskId > 1060) break;
    }
  }

  return reminders;
}
