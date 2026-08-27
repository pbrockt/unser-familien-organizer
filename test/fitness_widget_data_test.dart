import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_widget_data.dart';
import 'package:flutter_test/flutter_test.dart';

Activity fahrt(String datum, int minuten, {double km = 10}) => Activity(
      id: '$datum-$minuten',
      date: datum,
      timeOfDay: '19:00',
      sportDetected: Sport.cycling,
      sportConfidence: 1,
      durationSec: minuten * 60,
      distanceKm: km,
      hrAvg: 140,
      hrMax: 160,
      hrHistogram: List<int>.filled(hrHistogramSize, 0),
      cadenceAvg: 80,
      speedAvgKmh: 20,
      speedMaxKmh: 30,
      elevGain: 0,
      elevLoss: 0,
      series: const [],
    );

String body({
  List<Activity> fahrten = const [],
  List<HealthDay> tage = const [],
}) =>
    buildFitnessWidgetBody(
      activities: fahrten,
      sportOf: (a) => a.sportEffective,
      healthDays: tage,
      stepGoal: 8000,
      today: DateTime(2026, 8, 27),
    );

FitnessWidgetData daten({
  List<Activity> fahrten = const [],
  List<HealthDay> tage = const [],
}) =>
    buildFitnessWidgetData(
      activities: fahrten,
      sportOf: (a) => a.sportEffective,
      healthDays: tage,
      stepGoal: 8000,
      today: DateTime(2026, 8, 27),
    );

void main() {
  group('Fortschritt fürs Widget', () {
    test('rechnet den Anteil am Wochenziel in Prozent', () {
      // 60 von 120 Minuten.
      expect(daten(fahrten: [fahrt('2026-08-25', 60)]).progressPercent, 50);
    });

    test('bleibt über dem Ziel bei hundert', () {
      // Der Balken kann nicht voller als voll werden.
      expect(daten(fahrten: [fahrt('2026-08-25', 300)]).progressPercent, 100);
    });

    test('ist ohne Fahrt null', () {
      expect(daten(fahrten: [fahrt('2026-08-17', 90)]).progressPercent, 0);
    });

    test('liefert die Ampelfarbe der laufenden Woche', () {
      expect(daten(fahrten: [fahrt('2026-08-25', 30)]).colorHex, '#C0503F');
      expect(daten(fahrten: [fahrt('2026-08-25', 110)]).colorHex, '#C8992F');
      expect(daten(fahrten: [fahrt('2026-08-25', 130)]).colorHex, '#3E8E51');
    });

    test('Farbe ist immer ein gültiger Hex-Wert', () {
      // Die native Seite parst sie mit Color.parseColor — ein Tippfehler faellt
      // dort auf die Ersatzfarbe zurueck, ohne dass es jemand merkt.
      for (final minuten in [0, 30, 110, 130, 300]) {
        final farbe = daten(fahrten: [fahrt('2026-08-25', minuten)]).colorHex;
        expect(farbe, matches(RegExp(r'^#[0-9A-Fa-f]{6}$')));
      }
    });
  });

  group('Widget-Inhalt', () {
    test('nennt die Minuten der laufenden Woche', () {
      final text = body(fahrten: [fahrt('2026-08-24', 45), fahrt('2026-08-26', 30)]);
      expect(text, contains('DIESE WOCHE'));
      expect(text, contains('75 von 120 Minuten'));
      expect(text, contains('2 Fahrten'));
    });

    test('meldet eine leere Woche als solche', () {
      final text = body(fahrten: [fahrt('2026-08-17', 60)]);
      expect(text, contains('noch keine Fahrt'));
    });

    test('setzt ein Sternchen ab 140 Minuten', () {
      expect(body(fahrten: [fahrt('2026-08-25', 145)]), contains('*'));
      expect(body(fahrten: [fahrt('2026-08-25', 120)]), isNot(contains('*')));
    });

    test('zeigt die Vorwoche nur, wenn dort etwas war', () {
      expect(
        body(fahrten: [fahrt('2026-08-17', 90), fahrt('2026-08-25', 30)]),
        contains('LETZTE WOCHE'),
      );
      expect(
        body(fahrten: [fahrt('2026-08-25', 30)]),
        isNot(contains('LETZTE WOCHE')),
      );
    });

    test('nimmt die Schritte-Serie mit, wenn es eine gibt', () {
      final text = body(
        fahrten: [fahrt('2026-08-25', 30)],
        tage: const [
          HealthDay(date: '2026-08-25', steps: 9000),
          HealthDay(date: '2026-08-26', steps: 9500),
          HealthDay(date: '2026-08-27', steps: 8200),
        ],
      );
      expect(text, contains('3 Tage in Folge'));
    });

    test('lässt die Serie weg, wenn keine läuft', () {
      final text = body(
        fahrten: [fahrt('2026-08-25', 30)],
        tage: const [HealthDay(date: '2026-08-25', steps: 3000)],
      );
      expect(text, isNot(contains('in Folge')));
    });
  });

  group('Format', () {
    // Die Daten landen in einer SharedPreferences-XML. Steuerzeichen ausser dem
    // Tabulator zerbrechen sie, und dann bleibt das Widget einfach leer — ohne
    // Fehlermeldung. Genau deshalb wird das hier geprüft.
    test('enthält keine Steuerzeichen außer Tabulator und Zeilenumbruch', () {
      final text = body(
        fahrten: [fahrt('2026-08-24', 45), fahrt('2026-08-17', 150)],
        tage: const [HealthDay(date: '2026-08-26', steps: 9000)],
      );
      for (final zeichen in text.runes) {
        if (zeichen == 9 || zeichen == 10) continue;
        expect(zeichen, greaterThanOrEqualTo(32),
            reason: 'Steuerzeichen U+${zeichen.toRadixString(16)} gefunden');
      }
    });

    test('markierte Zeilen tragen eine gültige Farbe vor dem Tabulator', () {
      final text = body(fahrten: [fahrt('2026-08-24', 45)]);
      final markiert = text.split('\n').where((z) => z.contains('\t'));
      expect(markiert, isNotEmpty);
      for (final zeile in markiert) {
        final farbe = zeile.split('\t').first;
        expect(farbe, matches(RegExp(r'^#[0-9A-Fa-f]{6}$')),
            reason: 'Ungültige Farbe: $farbe');
      }
    });

    test('Überschriften stehen komplett in Großbuchstaben', () {
      // Nur so setzt die native Seite sie fett ab.
      final text = body(fahrten: [fahrt('2026-08-24', 45)]);
      expect(text.split('\n').first, 'DIESE WOCHE');
    });
  });
}
