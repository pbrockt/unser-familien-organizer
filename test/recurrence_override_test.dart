import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';

const _series = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//FamilyPlanner//test//
BEGIN:VEVENT
UID:series-1
DTSTAMP:20260101T120000Z
DTSTART:20260601T090000
DTEND:20260601T100000
SUMMARY:Standup
RRULE:FREQ=DAILY;COUNT=10
END:VEVENT
BEGIN:VEVENT
UID:series-1
DTSTAMP:20260101T120000Z
RECURRENCE-ID:20260603T090000
DTSTART:20260603T140000
DTEND:20260603T150000
SUMMARY:Standup (verschoben)
END:VEVENT
END:VCALENDAR''';

void main() {
  const parser = IcalParser();
  const builder = IcalBuilder();

  test('erkennt Master + Override (RECURRENCE-ID)', () {
    final events = parser.parseEvents(_series);
    expect(events, hasLength(2));

    final master = events.firstWhere((e) => e.recurrence != null);
    expect(master.isOverride, isFalse);

    final override = events.firstWhere((e) => e.isOverride);
    expect(override.recurrenceId!.day, 3);
    expect(override.start.hour, 14); // verschoben auf 14 Uhr
  });

  test('excludeOccurrence fügt EXDATE hinzu', () {
    final updated = builder.excludeOccurrence(
      _series,
      DateTime(2026, 6, 5, 9),
      allDay: false,
    );
    final events = parser.parseEvents(updated);
    final master = events.firstWhere((e) => e.recurrence != null);
    expect(master.exDates.any((d) => d.day == 5), isTrue);
  });

  test('excludeOccurrence auf Override-Tag entfernt die Override-Instanz', () {
    final updated = builder.excludeOccurrence(
      _series,
      DateTime(2026, 6, 3, 9),
      allDay: false,
    );
    final events = parser.parseEvents(updated);
    // Override (3.) ist weg → nur noch der Master übrig.
    expect(events.where((e) => e.isOverride), isEmpty);
    final master = events.firstWhere((e) => e.recurrence != null);
    expect(master.exDates.any((d) => d.day == 3), isTrue);
  });
}
