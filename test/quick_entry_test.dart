import 'package:family_planner/features/calendar/quick_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Referenz-„jetzt": Mittwoch, 10. Juni 2026, 09:00.
  final now = DateTime(2026, 6, 10, 9, 0);

  test('„Zahnarzt morgen 15 Uhr"', () {
    final e = parseQuickEntry('Zahnarzt morgen 15 Uhr', now);
    expect(e.title, 'Zahnarzt');
    expect(e.allDay, isFalse);
    expect(e.start, DateTime(2026, 6, 11, 15, 0));
  });

  test('„Meeting heute 14:30"', () {
    final e = parseQuickEntry('Meeting heute 14:30', now);
    expect(e.title, 'Meeting');
    expect(e.start, DateTime(2026, 6, 10, 14, 30));
  });

  test('ohne Uhrzeit → Ganztags', () {
    final e = parseQuickEntry('Urlaub übermorgen', now);
    expect(e.title, 'Urlaub');
    expect(e.allDay, isTrue);
    expect(e.start, DateTime(2026, 6, 12));
  });

  test('Wochentag → nächstes Vorkommen', () {
    // Mittwoch 10.6. → nächster Freitag = 12.6.
    final e = parseQuickEntry('Sport freitag 18 uhr', now);
    expect(e.title, 'Sport');
    expect(e.start, DateTime(2026, 6, 12, 18, 0));
  });

  test('explizites Datum „am 5.7. 10 Uhr"', () {
    final e = parseQuickEntry('Grillen am 5.7. 10 Uhr', now);
    expect(e.title, 'Grillen');
    expect(e.start, DateTime(2026, 7, 5, 10, 0));
  });

  test('Datum in Vergangenheit ohne Jahr → nächstes Jahr', () {
    final e = parseQuickEntry('Steuer 1.1.', now);
    expect(e.start, DateTime(2027, 1, 1));
  });

  test('„15h" wird als Uhrzeit erkannt', () {
    final e = parseQuickEntry('Anruf morgen 15h', now);
    expect(e.allDay, isFalse);
    expect(e.start.hour, 15);
  });

  test('Titel mit Artikel bleibt erhalten', () {
    final e = parseQuickEntry('Die Toten Hosen Konzert morgen', now);
    expect(e.title, 'Die Toten Hosen Konzert');
    expect(e.allDay, isTrue);
  });

  test('Kalendername wird erkannt und aus dem Titel entfernt', () {
    final e = parseQuickEntry(
      'Meeting morgen 10 Uhr Arbeit',
      now,
      calendarNames: ['Arbeit', 'Persönlich'],
    );
    expect(e.title, 'Meeting');
    expect(e.calendarName, 'Arbeit');
    expect(e.start, DateTime(2026, 6, 11, 10, 0));
  });

  test('ohne erkannten Kalender bleibt calendarName null', () {
    final e = parseQuickEntry(
      'Zahnarzt morgen 15 Uhr',
      now,
      calendarNames: ['Arbeit', 'Persönlich'],
    );
    expect(e.calendarName, isNull);
    expect(e.title, 'Zahnarzt');
  });
}
