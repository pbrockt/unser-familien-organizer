import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_weekly.dart';
import 'package:flutter_test/flutter_test.dart';

Activity fahrt(String datum, int minuten,
        {double km = 10, Sport sport = Sport.cycling}) =>
    Activity(
      id: '$datum-$minuten',
      date: datum,
      timeOfDay: '19:00',
      sportDetected: sport,
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

Sport sportOf(Activity a) => a.sportDetected;

void main() {
  // Donnerstag, 27.08.2026. Die Woche läuft also noch.
  final donnerstag = DateTime(2026, 8, 27);

  group('Wochen fürs Wischen', () {
    test('liefert vergangene, laufende und kommende Woche in dieser Reihenfolge', () {
      // Links Vergangenheit, rechts Zukunft — anders herum wischte man nach links
      // in die Zukunft.
      final wochen = cyclingWeeks(const [], sportOf, donnerstag);
      expect(wochen.length, 3);
      expect(wochen[0].monday, DateTime(2026, 8, 17));
      expect(wochen[1].monday, DateTime(2026, 8, 24));
      expect(wochen[2].monday, DateTime(2026, 8, 31));

      expect(wochen[0].isComplete, isTrue);
      expect(wochen[1].isCurrent, isTrue);
      expect(wochen[2].isFuture, isTrue);
    });

    test('zählt die Fahrten der laufenden Woche zusammen', () {
      final wochen = cyclingWeeks([
        fahrt('2026-08-24', 45), // Montag
        fahrt('2026-08-26', 30), // Mittwoch
      ], sportOf, donnerstag);

      final diese = wochen[1];
      expect(diese.minutes, 75);
      expect(diese.rides, 2);
      expect(diese.sunday, DateTime(2026, 8, 30));
    });

    test('verteilt die Minuten auf die Wochentage', () {
      final diese = cyclingWeeks([
        fahrt('2026-08-24', 45), // Montag
        fahrt('2026-08-26', 30), // Mittwoch
        fahrt('2026-08-26', 15), // noch einmal Mittwoch
      ], sportOf, donnerstag)[1];

      expect(diese.dailyMinutes, [45, 0, 45, 0, 0, 0, 0]);
      expect(diese.dailyMinutes.length, 7);
    });

    test('trennt sauber an der Wochengrenze', () {
      final wochen = cyclingWeeks([
        fahrt('2026-08-23', 60), // Sonntag der Vorwoche
        fahrt('2026-08-24', 40), // Montag der laufenden Woche
      ], sportOf, donnerstag);

      expect(wochen[0].minutes, 60);
      expect(wochen[1].minutes, 40);
    });

    test('zählt nur Radfahrten', () {
      final diese = cyclingWeeks([
        fahrt('2026-08-25', 50),
        fahrt('2026-08-25', 40, sport: Sport.running),
      ], sportOf, donnerstag)[1];

      expect(diese.minutes, 50);
      expect(diese.rides, 1);
    });

    test('die kommende Woche ist leer, aber vorhanden', () {
      final naechste = cyclingWeeks([fahrt('2026-08-25', 90)], sportOf, donnerstag)[2];
      expect(naechste.minutes, 0);
      expect(naechste.isFuture, isTrue);
      expect(naechste.isComplete, isFalse, reason: 'Nicht bewertbar');
    });

    test('kennt die Kalenderwoche', () {
      final diese = cyclingWeeks(const [], sportOf, donnerstag)[1];
      expect(diese.weekNumber, 35);
    });
  });

  group('Bewertung', () {
    test('unter 100 Minuten ist zu wenig', () {
      expect(weeklyLevel(0), WeeklyLevel.zuWenig);
      expect(weeklyLevel(99), WeeklyLevel.zuWenig);
    });

    test('100 bis 140 Minuten ist auf gutem Weg', () {
      expect(weeklyLevel(100), WeeklyLevel.fastGeschafft);
      expect(weeklyLevel(140), WeeklyLevel.fastGeschafft);
    });

    test('über 140 Minuten ist geschafft', () {
      expect(weeklyLevel(141), WeeklyLevel.geschafft);
      expect(weeklyLevel(300), WeeklyLevel.geschafft);
    });

    test('die Schwellen lassen sich verschieben', () {
      expect(weeklyLevel(80, lower: 60, upper: 90), WeeklyLevel.fastGeschafft);
      expect(weeklyLevel(100, lower: 60, upper: 90), WeeklyLevel.geschafft);
    });
  });

  group('Abgeschlossene Wochen fürs Einfärben', () {
    test('bewertet nur vergangene Wochen', () {
      final stufen = completedWeekLevels([
        fahrt('2026-08-17', 150), // Vorwoche: geschafft
        fahrt('2026-08-25', 200), // laufende Woche
      ], sportOf, donnerstag);

      expect(stufen[DateTime(2026, 8, 17)], WeeklyLevel.geschafft);
      expect(stufen.containsKey(DateTime(2026, 8, 24)), isFalse,
          reason: 'Die laufende Woche ist noch nicht entschieden');
    });

    test('summiert mehrere Fahrten einer Woche', () {
      final stufen = completedWeekLevels([
        fahrt('2026-08-17', 60),
        fahrt('2026-08-19', 55),
      ], sportOf, donnerstag);
      expect(stufen[DateTime(2026, 8, 17)], WeeklyLevel.fastGeschafft);
    });

    test('Wochen ganz ohne Fahrt tauchen nicht auf', () {
      // Ohne Fahrt gibt es nichts einzufärben — ein rotes Kästchen für jede Woche
      // seit Jahresbeginn wäre nur Lärm.
      final stufen = completedWeekLevels(
        [fahrt('2026-08-17', 60)],
        sportOf,
        donnerstag,
      );
      expect(stufen.keys, [DateTime(2026, 8, 17)]);
    });
  });

  test('mondayOf findet den Wochenanfang', () {
    expect(mondayOf(DateTime(2026, 8, 27)), DateTime(2026, 8, 24));
    expect(mondayOf(DateTime(2026, 8, 24)), DateTime(2026, 8, 24));
    expect(mondayOf(DateTime(2026, 8, 30)), DateTime(2026, 8, 24),
        reason: 'Sonntag gehört zur Woche davor');
  });
}
