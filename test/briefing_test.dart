import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:family_planner/features/settings/briefing_planner.dart';
import 'package:family_planner/features/tasks/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent _ev(DateTime start) =>
    CalendarEvent(uid: 'e', summary: 's', start: start);

TaskItem _task({DateTime? due, bool completed = false}) => TaskItem(
  uid: 't',
  summary: 'Aufgabe',
  objectHref: 'o',
  etag: 'e',
  rawIcal: 'BEGIN:VTODO\nEND:VTODO',
  due: due,
  completed: completed,
);

void main() {
  test('deaktiviert → null', () {
    final r = planDailyBriefing(
      events: const [],
      taskLists: const [],
      enabled: false,
      minutesOfDay: 7 * 60,
      now: DateTime(2026, 6, 22, 6),
    );
    expect(r, isNull);
  });

  test('vor der Briefing-Zeit → heute, zählt heutige Termine/Aufgaben', () {
    final now = DateTime(2026, 6, 22, 6); // 06:00, Briefing 07:00
    final events = [_ev(DateTime(2026, 6, 22, 10)), _ev(DateTime(2026, 6, 23, 9))];
    final lists = [
      TaskList(href: 'l', name: 'L', items: [
        _task(due: DateTime(2026, 6, 22)),
        _task(due: DateTime(2026, 6, 25)), // später → nicht fällig heute
      ]),
    ];
    final r = planDailyBriefing(
      events: events,
      taskLists: lists,
      enabled: true,
      minutesOfDay: 7 * 60,
      now: now,
    );
    expect(r, isNotNull);
    expect(r!.when, DateTime(2026, 6, 22, 7));
    expect(r.body, contains('1 Termin'));
    expect(r.body, contains('1 fällige Aufgabe'));
  });

  test('nach der Briefing-Zeit → morgen', () {
    final now = DateTime(2026, 6, 22, 8); // nach 07:00
    final r = planDailyBriefing(
      events: const [],
      taskLists: const [],
      enabled: true,
      minutesOfDay: 7 * 60,
      now: now,
    );
    expect(r!.when, DateTime(2026, 6, 23, 7));
    expect(r.body, contains('Keine Termine'));
  });

  test('überfällige Aufgaben zählen mit', () {
    final now = DateTime(2026, 6, 22, 6);
    final lists = [
      TaskList(href: 'l', name: 'L', items: [
        _task(due: DateTime(2026, 6, 20)), // überfällig
      ]),
    ];
    final r = planDailyBriefing(
      events: const [],
      taskLists: lists,
      enabled: true,
      minutesOfDay: 7 * 60,
      now: now,
    );
    expect(r!.body, contains('1 fällige Aufgabe'));
  });
}
