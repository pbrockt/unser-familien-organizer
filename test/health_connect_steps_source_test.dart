import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_parsers.dart';
import 'package:family_planner/features/fitness/health_connect_file.dart';
import 'package:family_planner/features/fitness/health_connect_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

HcSample _schritte(DateTime t, double n, String quelle) => HcSample(
      kind: HcKind.steps,
      from: t,
      to: t.add(const Duration(minutes: 10)),
      value: n,
      source: quelle,
    );

void main() {
  // Ein echter Fall vom 18.10.: Uhr 1158, Handy zählt zusätzlich mit, Health Connect
  // meldet in Summe 1433.
  final tag = DateTime(2026, 10, 18);
  final proben = [
    _schritte(tag.add(const Duration(hours: 8)), 700, 'Huawei Health'),
    _schritte(tag.add(const Duration(hours: 12)), 458, 'Huawei Health'),
    _schritte(tag.add(const Duration(hours: 9)), 900, 'Google Fit'),
  ];
  const summe = {'2026-10-18': 1433};

  test('automatisch: die Summe von Health Connect, und das steht dabei', () {
    final t = healthDaysFromHc(samples: proben, stepsPerDay: summe).single;
    expect(t.steps, 1433);
    expect(t.stepsSource, kStepsSourceAll);
  });

  test('mit gewählter Uhr: nur ihre Schritte', () {
    final t = healthDaysFromHc(
      samples: proben,
      stepsPerDay: summe,
      stepsSource: 'Huawei Health',
    ).single;
    expect(t.steps, 1158);
    expect(t.stepsSource, 'Huawei Health');
  });

  test('eine Quelle ohne Schritte an dem Tag ergibt keine Schritte statt null', () {
    final t = healthDaysFromHc(
      samples: [
        ...proben,
        HcSample(
          kind: HcKind.restingHr,
          from: tag.add(const Duration(hours: 6)),
          to: tag.add(const Duration(hours: 6)),
          value: 55,
          source: 'Huawei Health',
        ),
      ],
      stepsPerDay: summe,
      stepsSource: 'Samsung Health',
    ).single;
    expect(t.steps, isNull);
    expect(t.stepsSource, isNull);
    expect(t.restingHr, 55);
  });

  test('Schritte je App für die Auswahl', () {
    expect(stepsBySource(proben, '2026-10-18'), {'Huawei Health': 1158, 'Google Fit': 900});
  });

  test('die Quelle steht in der Tagesdatei und kommt zurück', () {
    final md = healthDayToMarkdown(
      const HealthDay(date: '2026-10-18', steps: 1158, stepsSource: 'Huawei Health'),
      stand: DateTime(2026, 10, 18, 20),
    );
    expect(md, contains('steps_source: "Huawei Health"'));
    final z = const HealthParser().parse(md, '2026-10-18.md')!;
    expect(z.steps, 1158);
    expect(z.stepsSource, 'Huawei Health');
    expect(HealthDay.fromJson(z.toJson()).stepsSource, 'Huawei Health');
  });

  test('beim Zusammenführen bleibt die Quelle bei ihren Schritten', () {
    const hc = HealthDay(date: 'd', steps: 1158, stepsSource: 'Huawei Health', fromHealthConnect: true);
    const alt = HealthDay(date: 'd', steps: 1400, sleepHours: 7);
    final m = addHealthDay(alt, hc);
    expect(m.steps, 1158);
    expect(m.stepsSource, 'Huawei Health');
    final ohne = addHealthDay(alt, const HealthDay(date: 'd', fromHealthConnect: true));
    expect(ohne.steps, 1400);
    expect(ohne.stepsSource, isNull);
  });
}
