import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/weight_analysis.dart';

final DateTime _start = DateTime(2026, 6, 1);

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

WeightEntry entry(int dayOffset, double kg) =>
    WeightEntry(_iso(_start.add(Duration(days: dayOffset))), kg);

/// Täglich gewogen, gleichmäßig abnehmend, mit dem üblichen Rauschen.
List<WeightEntry> taeglich(
  int days,
  double startKg,
  double perDay,
  List<double> noise,
) =>
    List.generate(
      days,
      (i) => entry(i, startKg + perDay * i + noise[i % noise.length]),
    );

void main() {
  group('Glättung', () {
    test('glättet über ein Kalenderfenster, nicht über die letzten Einträge', () {
      // Zwei Werte im Abstand von 30 Tagen: der zweite darf den ersten nicht mehr
      // "sehen", sonst wäre der Schnitt der Mittelwert beider.
      final avg = WeightAnalysis.movingAverage([entry(0, 100), entry(30, 90)]);
      expect(avg.length, 2);
      expect(avg[0].kg, closeTo(100, 0.001));
      expect(avg[1].kg, closeTo(90, 0.001),
          reason: 'Der alte Wert liegt außerhalb des 7-Tage-Fensters');
    });

    test('glättet Tagesrauschen weg', () {
      // Konstantes Gewicht mit ±1 kg Rauschen: der Schnitt muss deutlich ruhiger sein
      // als die Rohwerte — genau darum geht es bei der Anzeige.
      const noise = [1.0, -0.8, 0.6, -1.0, 0.9, -0.5, 0.2];
      final entries = taeglich(21, 90.0, 0.0, noise);
      final avg = WeightAnalysis.movingAverage(entries).skip(6).toList();

      final rohSpanne = entries.map((e) => e.kg).reduce((a, b) => a > b ? a : b) -
          entries.map((e) => e.kg).reduce((a, b) => a < b ? a : b);
      final glattSpanne = avg.map((e) => e.kg).reduce((a, b) => a > b ? a : b) -
          avg.map((e) => e.kg).reduce((a, b) => a < b ? a : b);

      expect(glattSpanne, lessThan(rohSpanne / 4),
          reason: 'Roh $rohSpanne vs. geglättet $glattSpanne');
    });

    test('Kurvenpunkte behalten den echten Tagesabstand', () {
      final pts = WeightAnalysis.toPoints([
        entry(0, 90),
        entry(3, 89.5),
        entry(20, 88),
      ]);
      expect(pts.map((p) => p.dayOffset).toList(), [0, 3, 20]);
    });
  });

  group('Rate', () {
    test('schätzt die Rate aus dem Verlauf', () {
      // 0,5 kg pro Woche runter entspricht rund 0,0714 kg pro Tag.
      const noise = [0.4, -0.3, 0.2, -0.4, 0.3, -0.2, 0.0];
      final entries = taeglich(28, 92.0, -0.5 / 7.0, noise);
      final rate = WeightAnalysis.ratePerWeek(entries, _start.add(const Duration(days: 27)));
      expect(rate, isNotNull);
      expect(rate!, closeTo(-0.5, 0.08));
    });

    test('gibt ohne belastbare Datenlage keine Rate zurück', () {
      expect(WeightAnalysis.ratePerWeek(const [], _start), isNull);
      expect(
        WeightAnalysis.ratePerWeek(
            [entry(0, 90), entry(7, 89), entry(14, 88)],
            _start.add(const Duration(days: 14))),
        isNull,
        reason: 'Drei Werte sind zu wenig',
      );
      expect(
        WeightAnalysis.ratePerWeek(
            [entry(0, 90), entry(2, 89), entry(4, 89.5), entry(6, 88.8)],
            _start.add(const Duration(days: 6))),
        isNull,
        reason: 'Unter zwei Wochen Abstand ist die Steigung Rauschen',
      );
    });

    test('nur alte Werte ergeben keine aktuelle Rate', () {
      // Alles liegt außerhalb des Betrachtungsfensters von vier Wochen.
      final entries = taeglich(20, 92.0, -0.07, const [0.0]);
      expect(
        WeightAnalysis.ratePerWeek(entries, _start.add(const Duration(days: 120))),
        isNull,
      );
    });
  });

  group('Bewertung und Prognose', () {
    test('bewertet ein gesundes Tempo als gut', () {
      final entries =
          taeglich(28, 92.0, -0.5 / 7.0, const [0.3, -0.2, 0.1, -0.3, 0.2, -0.1, 0.0]);
      final t = WeightAnalysis.analyse(entries, 85.0, _start.add(const Duration(days: 27)));
      expect(t.verdict, RateVerdict.gut);
    });

    test('warnt bei über einem Prozent Körpergewicht pro Woche', () {
      // 1,5 kg pro Woche bei rund 92 kg sind deutlich über der Ein-Prozent-Marke.
      final entries =
          taeglich(28, 92.0, -1.5 / 7.0, const [0.2, -0.2, 0.1, -0.1, 0.0, 0.1, -0.1]);
      final t = WeightAnalysis.analyse(entries, 80.0, _start.add(const Duration(days: 27)));
      expect(t.verdict, RateVerdict.zuSchnell);
    });

    test('erkennt ein Plateau', () {
      final entries =
          taeglich(28, 90.0, 0.0, const [0.4, -0.3, 0.2, -0.4, 0.3, -0.2, 0.0]);
      final t = WeightAnalysis.analyse(entries, 85.0, _start.add(const Duration(days: 27)));
      expect(t.verdict, RateVerdict.plateau);
      expect(t.forecastDate, isNull,
          reason: 'Ohne Abwärtstrend darf es keine Prognose geben');
    });

    test('rechnet eine Prognose zum Ziel', () {
      final entries = taeglich(28, 92.0, -0.5 / 7.0, const [0.0]);
      final heute = _start.add(const Duration(days: 27));
      final t = WeightAnalysis.analyse(entries, 89.0, heute);

      expect(t.forecastDate, isNotNull);
      final wochen = t.forecastDate!.difference(heute).inDays / 7.0;
      // Trend liegt bei ~90,1 kg, also gut 1 kg über dem Ziel -> etwa zwei bis sechs Wochen.
      expect(wochen, inInclusiveRange(1.5, 6.0), reason: 'Prognose lag bei $wochen Wochen');
    });

    test('kein Ziel bedeutet keine Prognose', () {
      final entries = taeglich(28, 92.0, -0.5 / 7.0, const [0.0]);
      final t = WeightAnalysis.analyse(entries, null, _start.add(const Duration(days: 27)));
      expect(t.forecastDate, isNull);
      expect(t.toGoKg, isNull);
      expect(t.trendKg, isNotNull);
    });

    test('meldet ein bereits erreichtes Ziel', () {
      final entries = taeglich(28, 92.0, -0.5 / 7.0, const [0.0]);
      final t = WeightAnalysis.analyse(entries, 95.0, _start.add(const Duration(days: 27)));
      expect(t.toGoKg!, lessThan(0), reason: 'toGo muss negativ sein');
      expect(t.forecastDate, isNull,
          reason: 'Unter dem Ziel gibt es nichts zu prognostizieren');
    });

    test('kommt mit einem einzelnen Wert klar', () {
      final t = WeightAnalysis.analyse([entry(0, 91.3)], 85.0, _start);
      expect(t.trendKg!, closeTo(91.3, 0.001));
      expect(t.verdict, RateVerdict.zuWenigDaten);
      expect(t.forecastDate, isNull);
    });
  });
}
