import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:family_planner/features/settings/reminder_planner.dart';
import 'package:family_planner/features/tasks/task_item.dart';

void main() {
  final now = DateTime(2026, 6, 13, 8, 0);

  CalendarEvent ev(String s, DateTime start,
          {bool allDay = false, int? reminderMinutes}) =>
      CalendarEvent(
          uid: s,
          summary: s,
          start: start,
          allDay: allDay,
          reminderMinutes: reminderMinutes);

  TaskList list(List<TaskItem> items) =>
      TaskList(href: '/l/', name: 'L', items: items);

  TaskItem task(String s, DateTime? due) => TaskItem(
      uid: s, summary: s, objectHref: '/l/$s.ics', etag: 'e', rawIcal: 'X',
      due: due);

  test('Termin mit Erinnerung: Vorlaufzeit vor Beginn', () {
    final r = planReminders(
      events: [
        ev('Zahnarzt', DateTime(2026, 6, 13, 10, 0), reminderMinutes: 30)
      ],
      taskLists: const [],
      now: now,
    );
    expect(r, hasLength(1));
    expect(r.first.title, 'Zahnarzt');
    expect(r.first.when, DateTime(2026, 6, 13, 9, 30));
  });

  test('Termin ohne gesetzte Erinnerung ergibt keine Benachrichtigung', () {
    final r = planReminders(
      events: [ev('Ohne Erinnerung', DateTime(2026, 6, 13, 10, 0))],
      taskLists: const [],
      now: now,
    );
    expect(r, isEmpty);
  });

  test('Ganztags- und vergangene Termine ergeben keine Erinnerung', () {
    final r = planReminders(
      events: [
        ev('Urlaub', DateTime(2026, 6, 14), allDay: true, reminderMinutes: 30),
        ev('Vorbei', DateTime(2026, 6, 13, 7, 0), reminderMinutes: 30),
      ],
      taskLists: const [],
      now: now,
    );
    expect(r, isEmpty);
  });

  test('Aufgabe mit Fälligkeit (Datum) → Erinnerung um 9 Uhr', () {
    final r = planReminders(
      events: const [],
      taskLists: [
        list([task('Müll rausbringen', DateTime(2026, 6, 14))])
      ],
      now: now,
    );
    expect(r, hasLength(1));
    expect(r.first.title, 'Aufgabe fällig');
    expect(r.first.body, 'Müll rausbringen');
    expect(r.first.when, DateTime(2026, 6, 14, 9, 0));
  });

  test('Erledigte/ohne Fälligkeit ergeben keine Aufgaben-Erinnerung', () {
    final r = planReminders(
      events: const [],
      taskLists: [
        list([task('Ohne Datum', null)])
      ],
      now: now,
    );
    expect(r, isEmpty);
  });
}
