import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_repository.dart';
import 'package:family_planner/features/fitness/fitness_screen.dart';
import 'package:flutter_test/flutter_test.dart';

Activity fahrt(String datum) => Activity(
      id: '$datum.csv',
      date: datum,
      timeOfDay: '19:00',
      sportDetected: Sport.cycling,
      sportConfidence: 1,
      durationSec: 1800,
      distanceKm: 10,
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

void main() {
  final heute = DateTime(2026, 8, 27);
  const heuteIso = '2026-08-27';

  group('Tagesliste', () {
    test('enthält heute, auch wenn nichts eingelesen ist', () {
      // Die Tagesdatei kommt erst am Folgemorgen. Ohne diese Zeile gäbe es den
      // heutigen Tag in der App gar nicht — und damit kein Gewichtsfeld.
      final tage = buildDays(const FitnessData(), today: heute);
      expect(tage.length, 1);
      expect(tage.single.date, heuteIso);
      expect(tage.single.health, isNull);
      expect(tage.single.activities, isEmpty);
    });

    test('setzt heute an den Anfang', () {
      final tage = buildDays(
        FitnessData(activities: [fahrt('2026-08-25')]),
        today: heute,
      );
      expect(tage.first.date, heuteIso);
      expect(tage.last.date, '2026-08-25');
    });

    test('führt heute nicht doppelt, wenn es schon Daten hat', () {
      final tage = buildDays(
        FitnessData(activities: [fahrt(heuteIso)]),
        today: heute,
      );
      expect(tage.length, 1);
      expect(tage.single.activities.length, 1);
    });

    test('nimmt Tage auf, für die nur ein Gewicht vorliegt', () {
      // Sonst verschwände ein eingetragener Wert aus der Liste.
      final tage = buildDays(
        const FitnessData(),
        today: heute,
        alsoInclude: ['2026-08-20'],
      );
      expect(tage.map((t) => t.date), containsAll([heuteIso, '2026-08-20']));
    });

    test('sortiert neueste zuerst', () {
      final tage = buildDays(
        FitnessData(activities: [
          fahrt('2026-08-10'),
          fahrt('2026-08-26'),
          fahrt('2026-08-18'),
        ]),
        today: heute,
      );
      expect(
        tage.map((t) => t.date).toList(),
        [heuteIso, '2026-08-26', '2026-08-18', '2026-08-10'],
      );
    });
  });

  group('Einzelner Tag', () {
    test('liefert auch für ein leeres Datum einen Tag', () {
      // Der Tagesbildschirm muss jedes Datum öffnen können, sonst ließe sich dort
      // kein Gewicht eintragen.
      final tag = dayFor(const FitnessData(), heuteIso);
      expect(tag.date, heuteIso);
      expect(tag.health, isNull);
      expect(tag.activities, isEmpty);
    });

    test('findet Daten des gesuchten Tages', () {
      final daten = FitnessData(
        activities: [fahrt('2026-08-25'), fahrt('2026-08-26')],
        healthDays: const [HealthDay(date: '2026-08-25', steps: 9000)],
      );
      final tag = dayFor(daten, '2026-08-25');
      expect(tag.activities.length, 1);
      expect(tag.health?.steps, 9000);
    });
  });

  test('isoDate formatiert einstellige Monate und Tage', () {
    expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    expect(isoDate(DateTime(2026, 12, 31)), '2026-12-31');
  });
}
