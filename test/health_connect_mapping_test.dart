import 'package:family_planner/features/fitness/health_connect_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

HcSample _s(
  HcKind kind,
  DateTime from,
  double value, {
  DateTime? to,
  String source = 'Huawei Health',
}) =>
    HcSample(kind: kind, from: from, to: to ?? from, value: value, source: source);

void main() {
  group('Quelle je Art', () {
    test('nimmt die App mit den meisten Werten', () {
      final q = dominantSources([
        _s(HcKind.heartRate, DateTime(2026, 10, 10, 8), 60),
        _s(HcKind.heartRate, DateTime(2026, 10, 10, 9), 62),
        _s(HcKind.heartRate, DateTime(2026, 10, 10, 9), 90, source: 'Yazio'),
      ]);
      expect(q[HcKind.heartRate], 'Huawei Health');
    });

    test('zählt nichts doppelt, wenn zwei Apps dasselbe eintragen', () {
      final tage = healthDaysFromHc(samples: [
        _s(HcKind.activeKcal, DateTime(2026, 10, 10, 8), 200),
        _s(HcKind.activeKcal, DateTime(2026, 10, 10, 12), 300),
        _s(HcKind.activeKcal, DateTime(2026, 10, 10, 12), 500, source: 'Handy'),
      ]);
      expect(tage.single.activeCalories, 500);
    });
  });

  group('Schritte', () {
    test('die Summe von Health Connect geht vor', () {
      final tage = healthDaysFromHc(
        samples: [_s(HcKind.steps, DateTime(2026, 10, 10, 8), 1000)],
        stepsPerDay: {'2026-10-10': 8421},
      );
      expect(tage.single.steps, 8421);
    });

    test('ohne Summe zählt die dominante Quelle', () {
      final tage = healthDaysFromHc(samples: [
        _s(HcKind.steps, DateTime(2026, 10, 10, 8), 1000),
        _s(HcKind.steps, DateTime(2026, 10, 10, 9), 2500),
      ]);
      expect(tage.single.steps, 3500);
    });
  });

  group('Schlaf', () {
    // Nacht von Freitag auf Samstag, 23:00 bis 7:00, mit Phasen.
    final schlaf = [
      _s(HcKind.sleepSession, DateTime(2026, 10, 9, 23), 0,
          to: DateTime(2026, 10, 10, 7)),
      _s(HcKind.sleepLight, DateTime(2026, 10, 9, 23), 0,
          to: DateTime(2026, 10, 10, 2)),
      _s(HcKind.sleepDeep, DateTime(2026, 10, 10, 2), 0,
          to: DateTime(2026, 10, 10, 4)),
      _s(HcKind.sleepAwake, DateTime(2026, 10, 10, 4), 0,
          to: DateTime(2026, 10, 10, 4, 30)),
      _s(HcKind.sleepRem, DateTime(2026, 10, 10, 4, 30), 0,
          to: DateTime(2026, 10, 10, 7)),
    ];

    test('gehört zum Tag des Aufwachens — auch die Phase vor Mitternacht', () {
      final tage = healthDaysFromHc(samples: schlaf);
      expect(tage.map((t) => t.date), ['2026-10-10']);
    });

    test('Schlafdauer ist die Summe der Phasen, ohne Wachzeit', () {
      final t = healthDaysFromHc(samples: schlaf).single;
      expect(t.sleepHours, closeTo(7.5, 0.01));
      expect(t.sleepDeepHours, closeTo(2, 0.01));
      expect(t.sleepCoreHours, closeTo(3, 0.01));
      expect(t.sleepRemHours, closeTo(2.5, 0.01));
      expect(t.sleepAwakeHours, closeTo(0.5, 0.01));
      expect(t.bedtime, '23:00');
      expect(t.wakeTime, '07:00');
    });

    test('ohne Phasen zählt die Sitzung', () {
      final t = healthDaysFromHc(samples: [schlaf.first]).single;
      expect(t.sleepHours, closeTo(8, 0.01));
    });
  });

  test('Puls, Ruhepuls, SpO₂, Gewicht je Tag', () {
    final t = healthDaysFromHc(samples: [
      _s(HcKind.heartRate, DateTime(2026, 10, 10, 8), 60),
      _s(HcKind.heartRate, DateTime(2026, 10, 10, 9), 120),
      _s(HcKind.restingHr, DateTime(2026, 10, 10, 6), 54),
      _s(HcKind.spo2, DateTime(2026, 10, 10, 3), 96),
      _s(HcKind.spo2, DateTime(2026, 10, 10, 4), 92),
      _s(HcKind.weight, DateTime(2026, 10, 10, 7), 81.4),
      _s(HcKind.distance, DateTime(2026, 10, 10, 12), 2500),
    ]).single;
    expect(t.hrAvg, 90);
    expect(t.hrMin, 60);
    expect(t.hrMax, 120);
    expect(t.restingHr, 54);
    expect(t.spo2Avg, 94);
    expect(t.spo2Min, 92);
    expect(t.weightKg, 81.4);
    expect(t.walkingRunningKm, closeTo(2.5, 0.001));
  });

  test('Trainings nur als Zusammenfassung', () {
    final t = healthDaysFromHc(samples: const [], workouts: [
      HcWorkout(
        from: DateTime(2026, 10, 10, 15),
        to: DateTime(2026, 10, 10, 16, 3),
        type: 'BIKING',
        source: 'Huawei Health',
        distanceM: 20800,
      ),
    ]).single;
    expect(t.workoutCount, 1);
    expect(t.workoutMinutes, 63);
    expect(t.workoutDistanceKm, closeTo(20.8, 0.01));
    expect(t.workouts, ['biking']);
  });
}
