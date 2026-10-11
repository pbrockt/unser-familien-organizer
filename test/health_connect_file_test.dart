import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_parsers.dart';
import 'package:family_planner/features/fitness/health_connect_file.dart';
import 'package:flutter_test/flutter_test.dart';

const _tag = HealthDay(
  date: '2026-10-11',
  steps: 8421,
  sleepHours: 7.5,
  sleepDeepHours: 1.25,
  bedtime: '23:10',
  wakeTime: '06:40',
  restingHr: 54,
  hrAvg: 71,
  spo2Avg: 96,
  weightKg: 81.4,
  activeCalories: 520,
  walkingRunningKm: 6.2,
  workoutCount: 1,
  workoutMinutes: 42,
  workouts: ['walking'],
);

void main() {
  final stand = DateTime(2026, 10, 11, 14, 30);

  test('die geschriebene Datei liest der normale Import wieder genauso', () {
    final md = healthDayToMarkdown(_tag, stand: stand);
    final zurueck = const HealthParser().parse(md, '2026-10-11.md')!;
    expect(zurueck.date, '2026-10-11');
    expect(zurueck.steps, 8421);
    expect(zurueck.sleepHours, 7.5);
    expect(zurueck.sleepDeepHours, 1.25);
    expect(zurueck.bedtime, '23:10');
    expect(zurueck.wakeTime, '06:40');
    expect(zurueck.restingHr, 54);
    expect(zurueck.spo2Avg, 96);
    expect(zurueck.weightKg, 81.4);
    expect(zurueck.walkingRunningKm, 6.2);
    expect(zurueck.workouts, ['walking']);
    expect(zurueck.fromHealthConnect, isTrue);
  });

  group('von Hand geändert?', () {
    test('frisch geschrieben gilt als unberührt', () {
      expect(isUntouchedHcFile(healthDayToMarkdown(_tag, stand: stand)), isTrue);
    });

    test('ein geänderter Wert schützt die Datei', () {
      final md = healthDayToMarkdown(_tag, stand: stand)
          .replaceFirst('steps: 8421', 'steps: 9000');
      expect(isUntouchedHcFile(md), isFalse);
    });

    test('ein neuer Wert von Hand schützt die Datei ebenfalls', () {
      final md = healthDayToMarkdown(_tag, stand: stand)
          .replaceFirst('quelle:', 'exercise_minutes: 30\nquelle:');
      expect(isUntouchedHcFile(md), isFalse);
    });

    test('eine fremde Datei ohne Prüfsumme wird nie überschrieben', () {
      expect(isUntouchedHcFile('---\ndate: 2026-10-11\nsteps: 5\n---\n'), isFalse);
    });

    test('ein neuer Zeitstempel allein ist keine Änderung', () {
      final alt = healthDayToMarkdown(_tag, stand: stand);
      expect(sameMeasuredValues(alt, _tag), isTrue);
      expect(
        sameMeasuredValues(alt, mergeHealthDays(const HealthDay(date: '2026-10-11', steps: 9999), _tag)),
        isFalse,
      );
    });
  });

  group('Zusammenführen mit älteren Tagesdateien', () {
    const alt = HealthDay(
      date: '2026-10-11',
      steps: 8000,
      exerciseMinutes: 35,
    );
    final hc = const HealthParser()
        .parse(healthDayToMarkdown(_tag, stand: stand), '2026-10-11.md')!;

    test('Health Connect gewinnt, die alte Datei füllt Lücken', () {
      final t = addHealthDay(alt, hc);
      expect(t.steps, 8421);
      expect(t.exerciseMinutes, 35);
      expect(t.fromHealthConnect, isTrue);
    });

    test('egal in welcher Reihenfolge die Dateien eingelesen werden', () {
      final t = addHealthDay(hc, alt);
      expect(t.steps, 8421);
      expect(t.exerciseMinutes, 35);
    });

    test('ohne Health Connect ersetzt die neue Datei die alte wie bisher', () {
      final t = addHealthDay(alt, const HealthDay(date: '2026-10-11', steps: 1));
      expect(t.steps, 1);
      expect(t.exerciseMinutes, isNull);
    });
  });
}
