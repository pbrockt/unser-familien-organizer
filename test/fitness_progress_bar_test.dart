import 'package:family_planner/features/fitness/fitness_week_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rendert den Balken in einer festen Breite, damit sich die gezeichnete Größe messen
/// lässt. Genau daran scheitert so ein Widget: Es sieht im Code richtig aus und fällt
/// im Layout auf null Pixel zusammen — sichtbar wird das nur beim Messen.
Future<Size> balkenGroesse(
  WidgetTester tester, {
  required List<int> minuten,
  bool muted = false,
  double breite = 200,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: breite,
            child: FitnessProgressBar(
              dailyMinutes: minuten,
              color: const Color(0xFF3E8E51),
              muted: muted,
            ),
          ),
        ),
      ),
    ),
  );
  final finder = find.byKey(FitnessProgressBar.fillKey);
  if (finder.evaluate().isEmpty) return Size.zero;
  return tester.getSize(finder);
}

void main() {
  group('Fortschrittsbalken', () {
    testWidgets('ist bei halbem Ziel halb so breit', (tester) async {
      // 60 von 120 Minuten.
      final groesse = await balkenGroesse(tester, minuten: [60, 0, 0, 0, 0, 0, 0]);
      expect(groesse.width, closeTo(100, 1));
      expect(groesse.height, greaterThan(0), reason: 'Ein Balken ohne Höhe ist unsichtbar');
    });

    testWidgets('füllt bei erreichtem Ziel die volle Breite', (tester) async {
      final groesse = await balkenGroesse(tester, minuten: [120, 0, 0, 0, 0, 0, 0]);
      expect(groesse.width, closeTo(200, 1));
    });

    testWidgets('läuft über dem Ziel nicht weiter', (tester) async {
      // Dafür gibt es das Sternchen — sonst müsste der Balken aus der Karte laufen.
      final groesse = await balkenGroesse(tester, minuten: [300, 0, 0, 0, 0, 0, 0]);
      expect(groesse.width, closeTo(200, 1));
    });

    testWidgets('zeichnet bei wenigen Minuten trotzdem etwas', (tester) async {
      // 15 von 120 sind schmal, dürfen aber nicht verschwinden.
      final groesse = await balkenGroesse(tester, minuten: [15, 0, 0, 0, 0, 0, 0]);
      expect(groesse.width, greaterThan(10));
    });

    testWidgets('auch fünf Minuten ergeben einen sichtbaren Stummel', (tester) async {
      // 5 von 120 wären rechnerisch 8 Pixel — ein Härchen, das man für nichts hält.
      final groesse = await balkenGroesse(tester, minuten: [5, 0, 0, 0, 0, 0, 0]);
      expect(groesse.width, greaterThanOrEqualTo(12));
      expect(groesse.height, greaterThan(0));
    });

    testWidgets('bleibt ohne Minuten leer', (tester) async {
      final groesse = await balkenGroesse(tester, minuten: List.filled(7, 0));
      expect(groesse, Size.zero);
    });

    testWidgets('füllt nichts, wenn die Woche noch nicht begonnen hat', (tester) async {
      final groesse =
          await balkenGroesse(tester, minuten: [60, 0, 0, 0, 0, 0, 0], muted: true);
      expect(groesse, Size.zero);
    });

    testWidgets('zeichnet mehrere Fahrtage als Abschnitte', (tester) async {
      await balkenGroesse(tester, minuten: [30, 0, 30, 0, 0, 0, 0]);
      // Zwei gefärbte Abschnitte plus eine Trennlinie.
      final abschnitte = find.descendant(
        of: find.byKey(FitnessProgressBar.fillKey),
        matching: find.byType(ColoredBox),
      );
      expect(abschnitte.evaluate().length, 3);
    });

    testWidgets('zeigt bei einer einzigen Fahrt keine Trennlinie', (tester) async {
      await balkenGroesse(tester, minuten: [60, 0, 0, 0, 0, 0, 0]);
      final abschnitte = find.descendant(
        of: find.byKey(FitnessProgressBar.fillKey),
        matching: find.byType(ColoredBox),
      );
      expect(abschnitte.evaluate().length, 1);
    });

    testWidgets('überlebt eine sehr schmale Karte', (tester) async {
      final groesse = await balkenGroesse(
        tester,
        minuten: [60, 0, 30, 0, 0, 0, 0],
        breite: 40,
      );
      expect(tester.takeException(), isNull);
      expect(groesse.width, greaterThan(0));
    });
  });
}
