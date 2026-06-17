import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';

void main() {
  const builder = IcalBuilder();
  const parser = IcalParser();

  test('Komma in Titel/Ort wird korrekt gespeichert und wieder gelesen', () {
    final ical = builder.buildEvent(
      uid: 'test-uid',
      summary: 'Einkauf, Aldi & Co',
      start: DateTime(2026, 6, 18, 10),
      end: DateTime(2026, 6, 18, 11),
      location: 'Hauptstr. 5, Hesel',
    );

    // Auf der Leitung muss das Komma escaped sein (gültiges iCal).
    expect(ical.contains(r'SUMMARY:Einkauf\, Aldi'), isTrue);

    final parsed = parser.parseEvents(ical).single;
    // Beim Lesen darf kein Backslash mehr auftauchen.
    expect(parsed.summary, 'Einkauf, Aldi & Co');
    expect(parsed.location, 'Hauptstr. 5, Hesel');
  });

  test('Semikolon und Zeilenumbruch werden korrekt entescaped', () {
    final ical = builder.buildEvent(
      uid: 'test-uid-2',
      summary: 'A; B',
      start: DateTime(2026, 6, 18, 10),
      end: DateTime(2026, 6, 18, 11),
      description: 'Zeile1\nZeile2',
    );
    final parsed = parser.parseEvents(ical).single;
    expect(parsed.summary, 'A; B');
    expect(parsed.description, 'Zeile1\nZeile2');
  });
}
