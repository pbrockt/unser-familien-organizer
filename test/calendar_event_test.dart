import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/features/calendar/calendar_event.dart';

CalendarEvent _ev({
  required DateTime start,
  DateTime? end,
  bool allDay = false,
}) =>
    CalendarEvent(uid: 'x', summary: 's', start: start, end: end, allDay: allDay);

void main() {
  test('eintägiger Termin: nur an seinem Tag', () {
    final e = _ev(
      start: DateTime(2026, 6, 10, 10),
      end: DateTime(2026, 6, 10, 11),
    );
    expect(e.isMultiDay, isFalse);
    expect(e.occursOn(DateTime(2026, 6, 10)), isTrue);
    expect(e.occursOn(DateTime(2026, 6, 11)), isFalse);
  });

  test('mehrtägiger Termin läuft an allen Tagen', () {
    final e = _ev(
      start: DateTime(2026, 6, 10, 18),
      end: DateTime(2026, 6, 12, 9),
    );
    expect(e.isMultiDay, isTrue);
    expect(e.occursOn(DateTime(2026, 6, 9)), isFalse);
    expect(e.occursOn(DateTime(2026, 6, 10)), isTrue);
    expect(e.occursOn(DateTime(2026, 6, 11)), isTrue);
    expect(e.occursOn(DateTime(2026, 6, 12)), isTrue);
    expect(e.occursOn(DateTime(2026, 6, 13)), isFalse);
  });

  test('Ganztags-Termin: DTEND exklusiv → letzter Tag korrekt', () {
    // 3 Tage: 10., 11., 12.; DTEND = 13. (exklusiv)
    final e = _ev(
      start: DateTime(2026, 6, 10),
      end: DateTime(2026, 6, 13),
      allDay: true,
    );
    expect(e.endDayInclusive, DateTime(2026, 6, 12));
    expect(e.occursOn(DateTime(2026, 6, 12)), isTrue);
    expect(e.occursOn(DateTime(2026, 6, 13)), isFalse);
  });

  test('einzelner Ganztags-Termin ist nicht mehrtägig', () {
    final e = _ev(
      start: DateTime(2026, 6, 10),
      end: DateTime(2026, 6, 11), // exklusiv
      allDay: true,
    );
    expect(e.isMultiDay, isFalse);
    expect(e.occursOn(DateTime(2026, 6, 10)), isTrue);
    expect(e.occursOn(DateTime(2026, 6, 11)), isFalse);
  });

  test('mehrtägiger Termin mit Uhrzeit: vorbei nach echtem Ende', () {
    // 10. Juni 18:00 – 12. Juni 18:00 (mit Uhrzeit, nicht ganztägig).
    final e = _ev(
      start: DateTime(2026, 6, 10, 18),
      end: DateTime(2026, 6, 12, 18),
    );
    expect(e.isMultiDay, isTrue);
    // Läuft noch am 12. um 17:00 → nicht vorbei.
    expect(e.hasPassed(DateTime(2026, 6, 12, 17)), isFalse);
    // Nach 18:00 am 12. → vorbei (auch wenn noch derselbe Tag).
    expect(e.hasPassed(DateTime(2026, 6, 12, 19)), isTrue);
  });

  test('mehrtägiger Ganztags-Termin: vorbei erst nach letztem Tag', () {
    final e = _ev(
      start: DateTime(2026, 6, 10),
      end: DateTime(2026, 6, 13), // exklusiv → letzter Tag 12.
      allDay: true,
    );
    // Am letzten Tag (12.) noch nicht vorbei.
    expect(e.hasPassed(DateTime(2026, 6, 12, 23)), isFalse);
    // Am Folgetag vorbei.
    expect(e.hasPassed(DateTime(2026, 6, 13, 1)), isTrue);
  });
}
