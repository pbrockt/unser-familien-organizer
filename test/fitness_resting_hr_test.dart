import 'package:family_planner/features/fitness/fitness_analysis.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_providers.dart';
import 'package:flutter_test/flutter_test.dart';

HealthDay tag(String datum, {int? min, int? avg}) =>
    HealthDay(date: datum, hrMin: min, hrAvg: avg);

List<HealthDay> reihe(DateTime start, List<int> werte) => [
      for (var i = 0; i < werte.length; i++)
        tag(
          start.add(Duration(days: i)).toIso8601String().substring(0, 10),
          min: werte[i],
        ),
    ];

void main() {
  group('Ruhepuls', () {
    test('nimmt das Tagesminimum, nicht den Tagesschnitt', () {
      // Der Tagesschnitt hängt daran, wie viel man sich bewegt hat — er misst den
      // Tag, nicht die Form.
      final t = analyseRestingHr([
        tag('2026-08-01', min: 52, avg: 78),
        tag('2026-08-02', min: 54, avg: 91),
      ]);
      expect(t.latest, 54);
      expect(t.lowest, 52);
    });

    test('weicht auf den Schnitt aus, wenn kein Minimum vorliegt', () {
      final t = analyseRestingHr([
        tag('2026-08-01', avg: 60),
        tag('2026-08-02', avg: 58),
      ]);
      expect(t.latest, 58);
    });

    test('erkennt einen fallenden Ruhepuls', () {
      // 30 Tage um 60, danach 30 Tage um 55.
      final werte = [...List.filled(30, 60), ...List.filled(30, 55)];
      final t = analyseRestingHr(reihe(DateTime(2026, 6, 1), werte));

      expect(t.avgPrev30, 60);
      expect(t.avg30, 55);
      expect(t.change, -5);
    });

    test('gibt ohne Vergleichszeitraum keine Veränderung an', () {
      // Zu wenig Vorgeschichte — eine Veränderung wäre Zufall.
      final t = analyseRestingHr(reihe(DateTime(2026, 8, 1), List.filled(20, 58)));
      expect(t.avg30, 58);
      expect(t.avgPrev30, isNull);
      expect(t.change, isNull);
    });

    test('verwirft unmögliche Messwerte', () {
      final t = analyseRestingHr([
        tag('2026-08-01', min: 5),
        tag('2026-08-02', min: 200),
        tag('2026-08-03', min: 55),
      ]);
      expect(t.series.length, 1, reason: 'Nur der plausible Wert bleibt');
      expect(t.latest, 55);
    });

    test('kommt ohne Daten klar', () {
      final t = analyseRestingHr(const []);
      expect(t.hasData, isFalse);
      expect(t.latest, isNull);
      expect(t.change, isNull);
    });

    test('behält den echten Tagesabstand im Verlauf', () {
      final t = analyseRestingHr([
        tag('2026-08-01', min: 58),
        tag('2026-08-05', min: 56),
        tag('2026-08-20', min: 54),
      ]);
      expect(t.series.map((e) => e.$1).toList(), [0, 4, 19]);
    });
  });

  group('Gewichtsliste einlesen', () {
    test('liest gültige Einträge', () {
      final liste = decodeWeightEntries(
        '[{"date":"2026-08-25","kg":90.4,"time":"07:15"},'
        '{"date":"2026-08-24","kg":90.9}]',
      );
      expect(liste.length, 2);
      expect(liste.first.date, '2026-08-24', reason: 'nach Datum sortiert');
      expect(liste.last.time, '07:15');
    });

    test('überspringt kaputte Einträge statt abzustürzen', () {
      // Eine beschädigte Sicherung darf die App nicht lahmlegen.
      final liste = decodeWeightEntries(
        '[{"date":"2026-08-25","kg":90.4},{"kg":12},{"date":"x"},"unsinn"]',
      );
      expect(liste.length, 1);
    });

    test('ergibt bei Unsinn eine leere Liste', () {
      expect(decodeWeightEntries('kein json'), isEmpty);
      expect(decodeWeightEntries('{}'), isEmpty);
      expect(decodeWeightEntries('[]'), isEmpty);
    });
  });
}
