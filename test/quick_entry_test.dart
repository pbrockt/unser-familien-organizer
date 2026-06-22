import 'package:family_planner/features/calendar/quick_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Referenz-„jetzt": Mittwoch, 10. Juni 2026, 09:00.
  final now = DateTime(2026, 6, 10, 9, 0);

  test('„Zahnarzt morgen 15 Uhr"', () {
    final e = parseQuickEntry('Zahnarzt morgen 15 Uhr', now);
    expect(e.kind, QuickKind.event);
    expect(e.title, 'Zahnarzt');
    expect(e.allDay, isFalse);
    expect(e.start, DateTime(2026, 6, 11, 15, 0));
  });

  test('ohne Uhrzeit → Ganztags', () {
    final e = parseQuickEntry('Urlaub übermorgen', now);
    expect(e.title, 'Urlaub');
    expect(e.allDay, isTrue);
    expect(e.start, DateTime(2026, 6, 12));
  });

  test('Titel mit Artikel bleibt erhalten', () {
    final e = parseQuickEntry('Die Toten Hosen Konzert morgen', now);
    expect(e.title, 'Die Toten Hosen Konzert');
  });

  test('Kalendername als Wort wird erkannt', () {
    final e = parseQuickEntry(
      'Meeting morgen 10 Uhr Arbeit',
      now,
      calendarNames: ['Arbeit', 'Persönlich'],
    );
    expect(e.title, 'Meeting');
    expect(e.targetName, 'Arbeit');
  });

  test('Prefix „Arbeit: Mathe in 10 Tagen"', () {
    final e = parseQuickEntry(
      'Arbeit: Mathe in 10 Tagen',
      now,
      calendarNames: ['Arbeit'],
    );
    expect(e.targetName, 'Arbeit');
    expect(e.title, 'Mathe');
    expect(e.allDay, isTrue);
    expect(e.start, DateTime(2026, 6, 20));
  });

  test('Typ „aufgabe: …"', () {
    final e = parseQuickEntry('aufgabe: Müll rausbringen freitag', now);
    expect(e.kind, QuickKind.task);
    expect(e.title, 'Müll rausbringen');
    expect(e.start, DateTime(2026, 6, 12)); // Freitag
  });

  test('Typ „einkauf: …"', () {
    final e = parseQuickEntry('einkauf: Milch', now);
    expect(e.kind, QuickKind.shopping);
    expect(e.title, 'Milch');
  });

  test('Typ „geburtstag: Max 5.6.1990" mit Alter im Titel', () {
    final e = parseQuickEntry('geburtstag: Max 5.6.1990', now);
    expect(e.kind, QuickKind.birthday);
    expect(e.allDay, isTrue);
    expect(e.rrule, 'FREQ=YEARLY');
    expect(e.birthYear, 1990);
    expect(e.title, 'Max (1990)');
    // Nächster 5.6. ab heute (10.6.2026) → 5.6.2027.
    expect(e.start, DateTime(2027, 6, 5));
  });

  test('Typ „vorlage: …" setzt saveAsTemplate', () {
    final e = parseQuickEntry('vorlage: Elternabend 18 Uhr', now);
    expect(e.kind, QuickKind.event);
    expect(e.saveAsTemplate, isTrue);
    expect(e.title, 'Elternabend');
  });

  test('Serie „jede Woche bis 31.12."', () {
    final e = parseQuickEntry('Sport jede woche 18 uhr bis 31.12.', now);
    expect(e.rrule, 'FREQ=WEEKLY;UNTIL=20261231');
    expect(e.title, 'Sport');
  });

  test('Serie „alle 2 wochen"', () {
    final e = parseQuickEntry('Putzen alle 2 wochen', now);
    expect(e.rrule, 'FREQ=WEEKLY;INTERVAL=2');
  });

  test('Serie „jeden Montag" + COUNT „10x"', () {
    final e = parseQuickEntry('Lauftreff jeden montag 7 uhr 10x', now);
    expect(e.rrule, 'FREQ=WEEKLY;COUNT=10');
    expect(e.start.weekday, DateTime.monday);
    expect(e.start.hour, 7);
  });

  test('Zeit-Bereich „14-16 Uhr" setzt Ende', () {
    final e = parseQuickEntry('Workshop morgen 14-16 Uhr', now);
    expect(e.start, DateTime(2026, 6, 11, 14, 0));
    expect(e.end, DateTime(2026, 6, 11, 16, 0));
  });

  test('Dauer „für 2 Stunden" setzt Ende', () {
    final e = parseQuickEntry('Kino morgen 20 uhr für 2 stunden', now);
    expect(e.start, DateTime(2026, 6, 11, 20, 0));
    expect(e.end, DateTime(2026, 6, 11, 22, 0));
  });

  test('„halb 4 nachmittags" → 15:30', () {
    final e = parseQuickEntry('Kaffee morgen halb 4 nachmittags', now);
    expect(e.start, DateTime(2026, 6, 11, 15, 30));
  });

  test('Erinnerung „30 min vorher"', () {
    final e = parseQuickEntry('Anruf morgen 15 uhr 30 min vorher', now);
    expect(e.reminderMinutes, 30);
    expect(e.title, 'Anruf');
  });

  test('„nächsten Montag"', () {
    final e = parseQuickEntry('Termin nächsten montag', now);
    // Mittwoch 10.6. → diese Woche Mo wäre vergangen; nächster Mo = 15.6.,
    // „nächsten" schiebt auf 22.6. (Folgewoche).
    expect(e.start.weekday, DateTime.monday);
    expect(e.start, DateTime(2026, 6, 22));
  });

  test('Ort „@Praxis"', () {
    final e = parseQuickEntry('Zahnarzt morgen 9 uhr @Zahnarztpraxis', now);
    expect(e.location, 'Zahnarztpraxis');
    expect(e.title, 'Zahnarzt');
  });

  test('„15h" wird als Uhrzeit erkannt', () {
    final e = parseQuickEntry('Anruf morgen 15h', now);
    expect(e.allDay, isFalse);
    expect(e.start.hour, 15);
  });

  test('„in 2 Wochen"', () {
    final e = parseQuickEntry('Kontrolle in 2 wochen', now);
    expect(e.start, DateTime(2026, 6, 24));
  });
}
