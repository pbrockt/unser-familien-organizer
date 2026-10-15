import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_parsers.dart';
import 'package:family_planner/features/fitness/health_connect_file.dart';
import 'package:family_planner/features/fitness/health_connect_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

HcSample _puls(DateTime t, double bpm) => HcSample(
      kind: HcKind.heartRate,
      from: t,
      to: t,
      value: bpm,
      source: 'Huawei Health',
    );

Activity _datei(String datum, String uhr, int sek) => Activity(
      id: 'bosch.fit',
      date: datum,
      timeOfDay: uhr,
      sportDetected: Sport.cycling,
      sportConfidence: 1,
      durationSec: sek,
      distanceKm: 20,
      hrAvg: 140,
      hrMax: 170,
      hrHistogram: List<int>.filled(hrHistogramSize, 0),
      cadenceAvg: 70,
      speedAvgKmh: 20,
      speedMaxKmh: 45,
      elevGain: 100,
      elevLoss: 100,
      series: const [],
    );

void main() {
  final start = DateTime(2026, 10, 15, 15, 30);
  final fahrt = HcWorkout(
    from: start,
    to: start.add(const Duration(minutes: 60)),
    type: 'BIKING',
    source: 'Huawei Health',
    distanceM: 20800,
    kcal: 412,
  );
  // Puls alle 30 s: erste halbe Stunde 130, zweite 150.
  final puls = [
    for (var i = 0; i < 120; i++)
      _puls(start.add(Duration(seconds: 30 * i)), i < 60 ? 130 : 150),
    _puls(start.subtract(const Duration(minutes: 5)), 70), // vor der Fahrt
  ];

  group('Trainings aus Health Connect', () {
    test('Rad mit Puls aus dem Zeitraum der Fahrt', () {
      final t = trainingsFromHc(workouts: [fahrt], samples: puls).single;
      expect(t.isCycling, isTrue);
      expect(t.durationSec, 3600);
      expect(t.hrAvg, 140);
      expect(t.hrMax, 150);
      expect(t.hrSeconds[130], 1800);
      expect(t.hrSeconds[150], 1800);
      expect(t.hrSeconds.containsKey(70), isFalse);
    });

    test('Spaziergänge und Kurzes bleiben außen vor', () {
      final gehen = HcWorkout(
        from: start,
        to: start.add(const Duration(minutes: 40)),
        type: 'WALKING',
        source: 'Huawei Health',
      );
      final kurz = HcWorkout(
        from: start,
        to: start.add(const Duration(minutes: 2)),
        type: 'BIKING',
        source: 'Huawei Health',
      );
      expect(trainingsFromHc(workouts: [gehen, kurz], samples: puls), isEmpty);
    });

    test('in die Tagesdatei und als Einheit zurück', () {
      final t = trainingsFromHc(workouts: [fahrt], samples: puls);
      final md = healthDayToMarkdown(
        const HealthDay(date: '2026-10-15', steps: 9000),
        stand: DateTime(2026, 10, 15, 18),
        trainings: t,
      );
      expect(md, contains('training_1: BIKING | 15:30:00 | 3600 s | 20800 m'));
      // Der normale Import liest den Tag wie bisher.
      expect(const HealthParser().parse(md, '2026-10-15.md')!.steps, 9000);

      final a = hcTrainingsFromMarkdown(md).single;
      expect(a.id, 'hc:2026-10-15 15:30:00');
      expect(a.sportEffective, Sport.cycling);
      expect(a.timeOfDay, '15:30');
      expect(a.durationSec, 3600);
      expect(a.distanceKm, closeTo(20.8, 0.001));
      expect(a.speedAvgKmh, closeTo(20.8, 0.01));
      expect(a.hrAvg, 140);
      expect(a.hrHistogram[150], 1800);
      expect(a.indoor, isFalse);
    });

    test('ein von Hand geändertes Training schützt die Datei', () {
      final md = healthDayToMarkdown(
        const HealthDay(date: '2026-10-15'),
        stand: DateTime(2026, 10, 15, 18),
        trainings: trainingsFromHc(workouts: [fahrt], samples: puls),
      ).replaceFirst('3600 s', '3300 s');
      expect(isUntouchedHcFile(md), isFalse);
      expect(hcTrainingsFromMarkdown(md).single.durationSec, 3300);
    });

    test('neue Fahrt am Tag zählt als Änderung', () {
      const tag = HealthDay(date: '2026-10-15', steps: 9000);
      final alt = healthDayToMarkdown(tag, stand: DateTime(2026, 10, 15, 12));
      expect(sameMeasuredValues(alt, tag), isTrue);
      expect(
        sameMeasuredValues(alt, tag,
            trainings: trainingsFromHc(workouts: [fahrt], samples: puls)),
        isFalse,
      );
    });
  });

  group('Doppelte Fahrten', () {
    final hc = hcTrainingsFromMarkdown(healthDayToMarkdown(
      const HealthDay(date: '2026-10-15'),
      stand: DateTime(2026, 10, 15, 18),
      trainings: trainingsFromHc(workouts: [fahrt], samples: puls),
    )).single;

    test('die FIT-Datei gewinnt bei derselben Fahrt', () {
      final r = withoutHcDuplicates([hc, _datei('2026-10-15', '15:32', 3400)]);
      expect(r.map((a) => a.id), ['bosch.fit']);
    });

    test('auch wenn die Uhr später gestartet wurde, solange es sich überschneidet', () {
      final r = withoutHcDuplicates([hc, _datei('2026-10-15', '15:05', 3600)]);
      expect(r.map((a) => a.id), ['bosch.fit']);
    });

    test('eine andere Fahrt am selben Tag bleibt', () {
      final r = withoutHcDuplicates([hc, _datei('2026-10-15', '08:00', 1800)]);
      expect(r, hasLength(2));
    });
  });
}
