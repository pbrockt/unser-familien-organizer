import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/weekly_report.dart';
import 'package:family_planner/features/nutrition/nutrition_models.dart';
import 'package:flutter_test/flutter_test.dart';

Activity _rad(String datum, int min) => Activity(
      id: '$datum-$min',
      date: datum,
      timeOfDay: '17:00',
      sportDetected: Sport.cycling,
      sportConfidence: 1,
      durationSec: min * 60,
      distanceKm: 20,
      hrAvg: 140,
      hrMax: 170,
      hrHistogram: List<int>.filled(hrHistogramSize, 0),
      cadenceAvg: 80,
      speedAvgKmh: 20,
      speedMaxKmh: 40,
      elevGain: 0,
      elevLoss: 0,
      series: const [],
    );

NutritionDay _essen(String d, double kcal) => NutritionDay(date: d).withEntries([
      MealEntry(time: '12:00', meal: Meal.mittag, name: 'x', grams: 1, kcal: kcal),
    ]);

void main() {
  // Woche Mo 12.10. – So 18.10.2026.
  final sonntag = DateTime(2026, 10, 18, 19);

  group('Zeitpunkt', () {
    test('mitten in der Woche: kommender Sonntag 19 Uhr', () {
      expect(nextReportTime(DateTime(2026, 10, 15, 9)), sonntag);
    });
    test('Sonntag vor 19 Uhr: heute', () {
      expect(nextReportTime(DateTime(2026, 10, 18, 18, 59)), sonntag);
    });
    test('Sonntag nach 19 Uhr: eine Woche später', () {
      expect(nextReportTime(DateTime(2026, 10, 18, 19, 1)), DateTime(2026, 10, 25, 19));
    });
  });

  test('alles zusammen in einer Zeile', () {
    final text = weeklyReportBody(
      sonntag: sonntag,
      activities: [
        _rad('2026-10-13', 60),
        _rad('2026-10-16', 70),
        _rad('2026-10-08', 300), // Vorwoche — zählt nicht
      ],
      sportOf: (a) => a.sportEffective,
      healthDays: const [
        HealthDay(date: '2026-10-12', steps: 8000),
        HealthDay(date: '2026-10-13', steps: 9000),
        HealthDay(date: '2026-10-14'), // keine Schritte — kein Nulltag
        HealthDay(date: '2026-10-05', steps: 30000), // Vorwoche
      ],
      nutrition: {
        '2026-10-12': _essen('2026-10-12', 1800),
        '2026-10-13': _essen('2026-10-13', 2200),
      },
      weights: const [
        WeightEntry('2026-09-20', 84.0),
        WeightEntry('2026-09-27', 83.6),
        WeightEntry('2026-10-04', 83.2),
        WeightEntry('2026-10-11', 82.8),
        WeightEntry('2026-10-18', 82.4),
      ],
    )!;
    expect(text, startsWith('Ø 8.500 Schritte · 🚲 130 Min in 2 Fahrten ✅ · Ø 2.000 kcal'));
    expect(text, contains('Gewicht −'));
    expect(text, endsWith('kg/Woche'));
  });

  test('unter dem Ziel steht das Ziel dabei', () {
    final text = weeklyReportBody(
      sonntag: sonntag,
      activities: [_rad('2026-10-13', 45)],
      sportOf: (a) => a.sportEffective,
      healthDays: const [],
      nutrition: const {},
      weights: const [],
    );
    expect(text, '🚲 45 Min (Ziel 120)');
  });

  test('ohne irgendwelche Daten keine Benachrichtigung', () {
    final r = planWeeklyReport(
      enabled: true,
      activities: const [],
      sportOf: (a) => a.sportEffective,
      healthDays: const [],
      nutrition: const {},
      weights: const [],
      now: DateTime(2026, 10, 15),
    );
    expect(r, isNull);
  });

  test('ausgeschaltet keine Benachrichtigung', () {
    final r = planWeeklyReport(
      enabled: false,
      activities: [_rad('2026-10-13', 60)],
      sportOf: (a) => a.sportEffective,
      healthDays: const [],
      nutrition: const {},
      weights: const [],
      now: DateTime(2026, 10, 15),
    );
    expect(r, isNull);
  });

  test('geplant mit eigener ID zum Sonntag', () {
    final r = planWeeklyReport(
      enabled: true,
      activities: [_rad('2026-10-13', 60)],
      sportOf: (a) => a.sportEffective,
      healthDays: const [],
      nutrition: const {},
      weights: const [],
      now: DateTime(2026, 10, 15),
    )!;
    expect(r.id, kWeeklyReportNotificationId);
    expect(r.when, sonntag);
    expect(r.title, 'Deine Woche 💪');
  });
}
