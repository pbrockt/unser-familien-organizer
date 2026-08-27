import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_weekly.dart';
import 'package:flutter_test/flutter_test.dart';

Activity fahrt(String datum, int minuten, {double km = 10, Sport sport = Sport.cycling}) =>
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
  // Mittwoch. Die Woche läuft also noch.
  final mittwoch = DateTime(2026, 8, 26);

  group('Wochenminuten', () {
    test('zählt die Fahrten der laufenden Woche zusammen', () {
      final wochen = cyclingWeeks([
        fahrt('2026-08-24', 45), // Montag
        fahrt('2026-08-26', 30), // Mittwoch
      ], sportOf, mittwoch);

      expect(wochen.first.minutes, 75);
      expect(wochen.first.rides, 2);
      expect(wochen.first.isCurrent, isTrue);
      expect(wochen.first.monday, DateTime(2026, 8, 24));
      expect(wochen.first.sunday, DateTime(2026, 8, 30));
    });

    test('trennt sauber an der Wochengrenze', () {
      final wochen = cyclingWeeks([
        fahrt('2026-08-23', 60), // Sonntag der Vorwoche
        fahrt('2026-08-24', 40), // Montag der laufenden Woche
      ], sportOf, mittwoch);

      expect(wochen[0].minutes, 40);
      expect(wochen[1].minutes, 60);
    });

    test('zählt nur Radfahrten', () {
      final wochen = cyclingWeeks([
        fahrt('2026-08-25', 50),
        fahrt('2026-08-25', 40, sport: Sport.running),
      ], sportOf, mittwoch);

      expect(wochen.first.minutes, 50);
      expect(wochen.first.rides, 1);
    });

    test('zeigt Wochen ohne Fahrt mit null Minuten', () {
      // Eine Lücke wegzulassen würde verschleiern, dass da nichts war.
      final wochen = cyclingWeeks([fahrt('2026-08-25', 90)], sportOf, mittwoch);
      expect(wochen.length, 6);
      expect(wochen[0].minutes, 90);
      expect(wochen[1].minutes, 0);
      expect(wochen[1].rides, 0);
    });

    test('summiert auch die Kilometer', () {
      final wochen = cyclingWeeks([
        fahrt('2026-08-24', 30, km: 12.5),
        fahrt('2026-08-25', 30, km: 7.5),
      ], sportOf, mittwoch);
      expect(wochen.first.km, closeTo(20.0, 0.001));
    });

    test('ohne Fahrten gibt es trotzdem die Wochenliste', () {
      final wochen = cyclingWeeks(const [], sportOf, mittwoch, weeks: 3);
      expect(wochen.length, 3);
      expect(wochen.every((w) => w.minutes == 0), isTrue);
    });
  });

  group('Reihenfolge fürs Wischen', () {
    test('liefert neueste Woche zuerst', () {
      final wochen = cyclingWeeks([fahrt('2026-08-25', 90)], sportOf, mittwoch,
          weeks: 4);
      expect(wochen.first.isCurrent, isTrue);
      expect(wochen.first.monday.isAfter(wochen.last.monday), isTrue);
    });

    test('umgedreht liegt die laufende Woche rechts', () {
      // Die Karte dreht die Liste um, damit Wischen nach links in die Vergangenheit
      // führt. Ohne das läge die Gegenwart links und man wischte in die Zukunft.
      final fuersWischen = cyclingWeeks(
        [fahrt('2026-08-25', 90)],
        sportOf,
        mittwoch,
        weeks: 4,
      ).reversed.toList();

      expect(fuersWischen.last.isCurrent, isTrue);
      expect(fuersWischen.first.monday, DateTime(2026, 8, 3),
          reason: 'Drei Wochen vor dem 24.08.');
      for (var i = 1; i < fuersWischen.length; i++) {
        expect(fuersWischen[i].monday.isAfter(fuersWischen[i - 1].monday), isTrue,
            reason: 'Von links nach rechts muss es aufsteigend sein');
      }
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
}
