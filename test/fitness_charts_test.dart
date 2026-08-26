import 'package:family_planner/features/fitness/fitness_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _rahmen(Widget kind) => MaterialApp(home: Scaffold(body: kind));

/// Ist überhaupt etwas gezeichnet worden?
///
/// Ein Diagramm, das still nichts rendert, sieht im Code völlig gesund aus — genau so
/// blieben sämtliche Verlaufskurven unsichtbar, weil die Leer-Prüfung nur die eine von
/// zwei Datenreihen betrachtete.
Finder _leinwand() => find.byType(CustomPaint);

void main() {
  group('FitnessLineChart', () {
    testWidgets('zeichnet, wenn nur die Linie gefüllt ist', (tester) async {
      await tester.pumpWidget(_rahmen(
        const FitnessLineChart(smoothed: [(0, 120.0), (60, 140.0), (120, 155.0)]),
      ));
      expect(_leinwand(), findsWidgets);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('zeichnet, wenn nur Einzelpunkte gefüllt sind', (tester) async {
      await tester.pumpWidget(_rahmen(
        const FitnessLineChart(points: [(0, 90.0), (3, 89.5)]),
      ));
      expect(_leinwand(), findsWidgets);
    });

    testWidgets('kommt mit einem einzelnen Wert klar', (tester) async {
      await tester.pumpWidget(_rahmen(
        const FitnessLineChart(smoothed: [(0, 91.3)]),
      ));
      expect(tester.takeException(), isNull);
      expect(_leinwand(), findsWidgets);
    });

    testWidgets('bleibt leer, wenn beide Reihen leer sind', (tester) async {
      await tester.pumpWidget(_rahmen(const FitnessLineChart()));
      // Nur der Scaffold-eigene CustomPaint darf übrig bleiben, kein Diagramm.
      expect(find.byType(FitnessLineChart), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('verkraftet extreme Ausreißer ohne Absturz', (tester) async {
      // PACE_spm des Trackers schnellt im Stillstand auf sechsstellige Werte.
      await tester.pumpWidget(_rahmen(
        const FitnessLineChart(
          smoothed: [(0, 0.12), (1, 0.13), (2, 527000.0), (3, 0.14), (4, 0.12)],
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(_leinwand(), findsWidgets);
    });
  });

  group('FitnessBarChart', () {
    testWidgets('zeichnet Balken mit Ziellinie', (tester) async {
      await tester.pumpWidget(_rahmen(
        const FitnessBarChart(
          values: [
            ChartValue('01.08', 8200),
            ChartValue('02.08', 5100),
            ChartValue('03.08', 9400),
          ],
          goal: 8000,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(_leinwand(), findsWidgets);
      // Achsenbeschriftung: erste, mittlere, letzte.
      expect(find.text('01.08'), findsOneWidget);
      expect(find.text('03.08'), findsOneWidget);
    });

    testWidgets('zeichnet den Platzhalter für heute gestrichelt', (tester) async {
      // Der letzte Balken darf nicht wie ein erreichter Tag aussehen, solange für
      // heute noch keine Daten vorliegen.
      await tester.pumpWidget(_rahmen(
        const FitnessBarChart(
          values: [
            ChartValue('24.08', 8200),
            ChartValue('25.08', 9400),
            ChartValue('26.08', 8000, pending: true),
          ],
          goal: 8000,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(_leinwand(), findsWidgets);
      expect(find.text('26.08'), findsOneWidget,
          reason: 'Heute muss an der Achse auftauchen');
    });

    testWidgets('bleibt bei leeren Werten leer', (tester) async {
      await tester.pumpWidget(_rahmen(const FitnessBarChart(values: [])));
      expect(tester.takeException(), isNull);
    });
  });
}
