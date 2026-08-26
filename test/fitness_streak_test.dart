import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_streak.dart';
import 'package:flutter_test/flutter_test.dart';

HealthDay tag(String datum, int schritte) =>
    HealthDay(date: datum, steps: schritte);

void main() {
  final heute = DateTime(2026, 8, 26);
  const ziel = 8000;

  group('Laufende Serie', () {
    test('zählt aufeinanderfolgende Tage über dem Ziel', () {
      final s = computeStepStreak([
        tag('2026-08-24', 9000),
        tag('2026-08-25', 8500),
        tag('2026-08-26', 12000),
      ], ziel, heute);

      expect(s.current, 3);
      expect(s.startDate, '2026-08-24');
      expect(s.lastDate, '2026-08-26');
    });

    test('ein Tag unter dem Ziel unterbricht', () {
      final s = computeStepStreak([
        tag('2026-08-23', 9000),
        tag('2026-08-24', 3000),
        tag('2026-08-25', 8500),
        tag('2026-08-26', 12000),
      ], ziel, heute);

      expect(s.current, 2, reason: 'Nur der 25. und 26.');
      expect(s.longest, 2);
    });

    test('ein Tag ohne Daten unterbricht ebenfalls', () {
      // Sonst würde eine Lücke in der Aufzeichnung die Serie künstlich verlängern.
      final s = computeStepStreak([
        tag('2026-08-23', 9000),
        tag('2026-08-25', 8500),
        tag('2026-08-26', 12000),
      ], ziel, heute);

      expect(s.current, 2);
    });

    test('heute ohne Daten reißt die Serie nicht ab', () {
      // Die Tagesdatei kommt morgens — bis dahin darf die Serie nicht auf null stehen.
      final s = computeStepStreak([
        tag('2026-08-24', 9000),
        tag('2026-08-25', 8500),
      ], ziel, heute);

      expect(s.current, 2);
      expect(s.lastDate, '2026-08-25');
    });

    test('zwei Tage ohne Erfolg beenden die Serie', () {
      final s = computeStepStreak([
        tag('2026-08-23', 9000),
        tag('2026-08-24', 9000),
      ], ziel, heute);

      expect(s.current, 0);
      expect(s.longest, 2, reason: 'Der Rekord bleibt erhalten');
      expect(s.hasStreak, isFalse);
    });

    test('genau am Ziel zählt als erreicht', () {
      final s = computeStepStreak([tag('2026-08-26', 8000)], ziel, heute);
      expect(s.current, 1);
    });

    test('knapp darunter zählt nicht', () {
      final s = computeStepStreak([tag('2026-08-26', 7999)], ziel, heute);
      expect(s.current, 0);
    });
  });

  group('Längste Serie', () {
    test('findet den Rekord auch weit in der Vergangenheit', () {
      final s = computeStepStreak([
        for (var i = 1; i <= 9; i++)
          tag('2026-07-${i.toString().padLeft(2, '0')}', 9000),
        tag('2026-08-25', 9000),
        tag('2026-08-26', 9000),
      ], ziel, heute);

      expect(s.longest, 9);
      expect(s.current, 2);
    });

    test('funktioniert über Monatsgrenzen hinweg', () {
      final s = computeStepStreak([
        tag('2026-07-30', 9000),
        tag('2026-07-31', 9000),
        tag('2026-08-01', 9000),
      ], ziel, DateTime(2026, 8, 1));

      expect(s.current, 3);
    });
  });

  group('Randfälle', () {
    test('ohne Daten keine Serie', () {
      final s = computeStepStreak(const [], ziel, heute);
      expect(s.current, 0);
      expect(s.longest, 0);
      expect(s.reachedDates, isEmpty);
    });

    test('Tage ohne Schrittzahl werden übergangen', () {
      final s = computeStepStreak([
        const HealthDay(date: '2026-08-25'),
        tag('2026-08-26', 9000),
      ], ziel, heute);
      expect(s.current, 1);
    });

    test('merkt sich alle erreichten Tage für den Kalender', () {
      final s = computeStepStreak([
        tag('2026-08-20', 9000),
        tag('2026-08-24', 3000),
        tag('2026-08-26', 9000),
      ], ziel, heute);
      expect(s.reachedDates, {'2026-08-20', '2026-08-26'});
    });
  });
}
