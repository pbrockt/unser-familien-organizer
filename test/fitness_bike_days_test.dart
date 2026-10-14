import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_providers.dart';
import 'package:flutter_test/flutter_test.dart';

Activity _einheit(String id, String datum, Sport sport) => Activity(
      id: id,
      date: datum,
      timeOfDay: '15:00',
      sportDetected: sport,
      sportConfidence: 1,
      durationSec: 3600,
      distanceKm: 20,
      hrAvg: 140,
      hrMax: 170,
      hrHistogram: List<int>.filled(hrHistogramSize, 0),
      cadenceAvg: 80,
      speedAvgKmh: 20,
      speedMaxKmh: 40,
      elevGain: 0,
      elevLoss: 0,
      series: const [],
    );

void main() {
  final rad = _einheit('rad.fit', '2026-10-11', Sport.cycling);
  final lauf = _einheit('lauf.csv', '2026-10-12', Sport.running);
  final unklar = _einheit('x.csv', '2026-10-13', Sport.unknown);

  test('nur Tage mit Radfahrt', () {
    expect(
      bikeDates([rad, lauf, unklar], (a) => a.sportEffective),
      {'2026-10-11'},
    );
  });

  test('die von Hand gesetzte Sportart zählt', () {
    final korrigiert = {unklar.id: Sport.cycling, rad.id: Sport.running};
    expect(
      bikeDates([rad, lauf, unklar], (a) => korrigiert[a.id] ?? a.sportEffective),
      {'2026-10-13'},
    );
  });

  test('zwei Fahrten am selben Tag ergeben einen Tag', () {
    final zweite = _einheit('rad2.fit', '2026-10-11', Sport.cycling);
    expect(bikeDates([rad, zweite], (a) => a.sportEffective), hasLength(1));
  });
}
