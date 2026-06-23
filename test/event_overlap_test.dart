import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:family_planner/features/calendar/conflict_check.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent _ev(
  String uid,
  DateTime start,
  DateTime end, {
  bool allDay = false,
}) =>
    CalendarEvent(uid: uid, summary: uid, start: start, end: end, allDay: allDay);

void main() {
  final events = [
    _ev('A', DateTime(2026, 6, 22, 10), DateTime(2026, 6, 22, 11)),
    _ev('B', DateTime(2026, 6, 22, 14), DateTime(2026, 6, 22, 15)),
    _ev('GanzTag', DateTime(2026, 6, 22), DateTime(2026, 6, 23), allDay: true),
  ];

  test('Überschneidung wird gefunden', () {
    final c = findConflicts(
      events: events,
      start: DateTime(2026, 6, 22, 10, 30),
      end: DateTime(2026, 6, 22, 10, 45),
      allDay: false,
    );
    expect(c.map((e) => e.uid), ['A']);
  });

  test('angrenzend (Ende == Start) ist kein Konflikt', () {
    final c = findConflicts(
      events: events,
      start: DateTime(2026, 6, 22, 11),
      end: DateTime(2026, 6, 22, 12),
      allDay: false,
    );
    expect(c, isEmpty);
  });

  test('ganztägige Termine werden ignoriert', () {
    final c = findConflicts(
      events: events,
      start: DateTime(2026, 6, 22, 9),
      end: DateTime(2026, 6, 22, 9, 30),
      allDay: false,
    );
    expect(c, isEmpty);
  });

  test('neuer Ganztags-Termin erzeugt keine Konflikte', () {
    final c = findConflicts(
      events: events,
      start: DateTime(2026, 6, 22),
      end: DateTime(2026, 6, 23),
      allDay: true,
    );
    expect(c, isEmpty);
  });

  test('eigener Termin via ignoreUid ausgeschlossen', () {
    final c = findConflicts(
      events: events,
      start: DateTime(2026, 6, 22, 10),
      end: DateTime(2026, 6, 22, 11),
      allDay: false,
      ignoreUid: 'A',
    );
    expect(c, isEmpty);
  });
}
