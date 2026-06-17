import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';

void main() {
  const builder = IcalBuilder();
  const parser = IcalParser();

  test('Erinnerung (VALARM) wird geschrieben und wieder gelesen', () {
    final ical = builder.buildEvent(
      uid: 'a1',
      summary: 'Zahnarzt',
      start: DateTime(2026, 6, 18, 10),
      end: DateTime(2026, 6, 18, 11),
      reminderMinutes: 15,
    );
    expect(ical.contains('BEGIN:VALARM'), isTrue);
    expect(ical.contains('TRIGGER:-PT15M'), isTrue);

    final parsed = parser.parseEvents(ical).single;
    expect(parsed.reminderMinutes, 15);
  });

  test('Ohne Erinnerung gibt es keinen VALARM', () {
    final ical = builder.buildEvent(
      uid: 'a2',
      summary: 'Ohne',
      start: DateTime(2026, 6, 18, 10),
      end: DateTime(2026, 6, 18, 11),
    );
    expect(ical.contains('BEGIN:VALARM'), isFalse);
    expect(parser.parseEvents(ical).single.reminderMinutes, isNull);
  });

  test('Beim Aktualisieren wird die Erinnerung entfernt/ersetzt', () {
    var ical = builder.buildEvent(
      uid: 'a3',
      summary: 'Termin',
      start: DateTime(2026, 6, 18, 10),
      end: DateTime(2026, 6, 18, 11),
      reminderMinutes: 30,
    );
    // Auf 1 Stunde ändern.
    ical = builder.updateEvent(
      ical,
      summary: 'Termin',
      start: DateTime(2026, 6, 18, 10),
      end: DateTime(2026, 6, 18, 11),
      reminderMinutes: 60,
    );
    expect('BEGIN:VALARM'.allMatches(ical).length, 1);
    expect(parser.parseEvents(ical).single.reminderMinutes, 60);

    // Erinnerung ausschalten.
    ical = builder.updateEvent(
      ical,
      summary: 'Termin',
      start: DateTime(2026, 6, 18, 10),
      end: DateTime(2026, 6, 18, 11),
      reminderMinutes: null,
    );
    expect(ical.contains('BEGIN:VALARM'), isFalse);
    expect(parser.parseEvents(ical).single.reminderMinutes, isNull);
  });
}
