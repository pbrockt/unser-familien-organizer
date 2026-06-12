import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';

const _masterOnly = '''BEGIN:VCALENDAR
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
END:VCALENDAR''';

const _withOverride = '''BEGIN:VCALENDAR
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
SUMMARY:Standup verschoben
END:VEVENT
END:VCALENDAR''';

void main() {
  const builder = IcalBuilder();
  const parser = IcalParser();

  test('upsertOverride fügt eine geänderte Einzel-Instanz hinzu', () {
    final updated = builder.upsertOverride(
      _masterOnly,
      recurrenceId: DateTime(2026, 6, 5, 9),
      summary: 'Verschoben',
      start: DateTime(2026, 6, 5, 14),
      end: DateTime(2026, 6, 5, 15),
    );
    final events = parser.parseEvents(updated);
    expect(events, hasLength(2));
    final override = events.firstWhere((e) => e.isOverride);
    expect(override.recurrenceId!.day, 5);
    expect(override.start.hour, 14);
    expect(override.summary, 'Verschoben');
  });

  test('upsertOverride ersetzt bestehenden Override am selben Tag', () {
    final updated = builder.upsertOverride(
      _withOverride,
      recurrenceId: DateTime(2026, 6, 3, 9),
      summary: 'Neu',
      start: DateTime(2026, 6, 3, 16),
      end: DateTime(2026, 6, 3, 17),
    );
    final events = parser.parseEvents(updated);
    final overrides = events.where((e) => e.isOverride).toList();
    expect(overrides, hasLength(1)); // ersetzt, nicht verdoppelt
    expect(overrides.first.start.hour, 16);
    expect(overrides.first.summary, 'Neu');
  });

  test('updateEvent ändert nur den Master, Override bleibt erhalten', () {
    final updated = builder.updateEvent(
      _withOverride,
      summary: 'Master neu',
      start: DateTime(2026, 6, 1, 8),
      end: DateTime(2026, 6, 1, 9),
    );
    final events = parser.parseEvents(updated);
    final master = events.firstWhere((e) => e.recurrence != null);
    final override = events.firstWhere((e) => e.isOverride);
    expect(master.summary, 'Master neu');
    expect(master.start.hour, 8);
    // Override unverändert:
    expect(override.summary, 'Standup verschoben');
    expect(override.start.hour, 14);
  });
}
