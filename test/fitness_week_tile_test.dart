import 'package:family_planner/features/fitness/fitness_week_list.dart';
import 'package:family_planner/features/fitness/fitness_weekly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

CyclingWeek woche(List<int> proTag, {bool aktuell = true, bool zukunft = false}) =>
    CyclingWeek(
      monday: DateTime(2026, 8, 24),
      minutes: proTag.fold<int>(0, (s, m) => s + m),
      km: 20,
      rides: proTag.where((m) => m > 0).length,
      dailyMinutes: proTag,
      isCurrent: aktuell,
      isFuture: zukunft,
    );

/// Rendert die Kachel so, wie sie auf der Startseite steckt: feste Höhe im PageView,
/// begrenzte Breite in der Karte.
Future<Size> balkenInKachel(WidgetTester tester, CyclingWeek w) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            child: Container(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                height: 74,
                child: PageView(
                  children: [FitnessWeekTile(woche: w, onTap: () {})],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final finder = find.byKey(FitnessProgressBar.fillKey);
  if (finder.evaluate().isEmpty) return Size.zero;
  return tester.getSize(finder);
}

void main() {
  testWidgets('Balken ist in der Kachel sichtbar', (tester) async {
    final groesse = await balkenInKachel(tester, woche([60, 0, 0, 0, 0, 0, 0]));
    expect(tester.takeException(), isNull);
    expect(groesse.height, greaterThan(0), reason: 'Höhe null = unsichtbar');
    expect(groesse.width, greaterThan(0), reason: 'Breite null = unsichtbar');
  });

  testWidgets('Kachel läuft nicht über', (tester) async {
    await balkenInKachel(tester, woche([60, 30, 0, 0, 0, 0, 0]));
    expect(tester.takeException(), isNull,
        reason: 'Ein Overflow klippt den Balken weg');
  });
}
