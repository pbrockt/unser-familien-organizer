import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';

void main() {
  const builder = IcalBuilder();
  const parser = IcalParser();

  test('buildEvent erzeugt einen parsebaren Termin mit Uhrzeit', () {
    final ical = builder.buildEvent(
      uid: 'e1',
      summary: 'Zahnarzt',
      start: DateTime(2026, 6, 20, 10, 0),
      end: DateTime(2026, 6, 20, 11, 0),
    );
    expect(ical, contains('BEGIN:VEVENT'));

    final events = parser.parseEvents(ical);
    expect(events, hasLength(1));
    expect(events.first.summary, 'Zahnarzt');
    expect(events.first.allDay, isFalse);
    expect(events.first.start.hour, 10);
  });

  test('buildEvent ganztägig schreibt VALUE=DATE und parst als Ganztags', () {
    final ical = builder.buildEvent(
      uid: 'e2',
      summary: 'Urlaub',
      start: DateTime(2026, 7, 1),
      allDay: true,
    );
    expect(ical, contains('VALUE=DATE'));

    final events = parser.parseEvents(ical);
    expect(events.first.allDay, isTrue);
    expect(events.first.summary, 'Urlaub');
  });

  test('updateEvent ändert Titel und Tag', () {
    final original = builder.buildEvent(
      uid: 'e3',
      summary: 'Alt',
      start: DateTime(2026, 6, 20, 9, 0),
      end: DateTime(2026, 6, 20, 10, 0),
    );
    final updated = builder.updateEvent(
      original,
      summary: 'Neu',
      start: DateTime(2026, 6, 21, 9, 0),
      end: DateTime(2026, 6, 21, 10, 0),
    );

    final events = parser.parseEvents(updated);
    expect(events.first.summary, 'Neu');
    expect(events.first.start.day, 21);
  });
}
