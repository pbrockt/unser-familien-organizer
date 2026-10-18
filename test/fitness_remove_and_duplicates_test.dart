import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_overrides.dart';
import 'package:family_planner/features/fitness/fitness_providers.dart';
import 'package:family_planner/features/fitness/fitness_repository.dart';
import 'package:family_planner/features/fitness/health_connect_mapping.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Activity _fahrt(String id, String uhr, {double km = 20, bool karte = false}) => Activity(
      id: id,
      date: '2026-10-18',
      timeOfDay: uhr,
      sportDetected: Sport.cycling,
      sportConfidence: 1,
      durationSec: 3600,
      distanceKm: km,
      hrAvg: 140,
      hrMax: 160,
      hrHistogram: List<int>.filled(hrHistogramSize, 0),
      cadenceAvg: 0,
      speedAvgKmh: 20,
      speedMaxKmh: 30,
      elevGain: 0,
      elevLoss: 0,
      series: karte
          ? const [
              TrackPoint(elapsedSec: 0, hr: 120, speedKmh: 20, cadence: 0, altitude: 200, lat: 49.7, lon: 7.6),
              TrackPoint(elapsedSec: 60, hr: 130, speedKmh: 21, cadence: 0, altitude: 201, lat: 49.71, lon: 7.61),
            ]
          : const [],
    );

class _Repo extends FitnessRepository {
  _Repo(this.daten);
  final FitnessData daten;
  @override
  Future<FitnessData> load() async => daten;
}

void main() {
  group('Doppelte gleichen Rangs', () {
    test('Huawei und Bosch in Health Connect: eine Fahrt, die mit Karte gewinnt', () {
      final huawei = _fahrt('2026-10-18_153000_rad_hc.csv', '15:30', karte: true);
      final bosch = _fahrt('2026-10-18_153105_rad_hc.csv', '15:31');
      expect(withoutHcDuplicates([bosch, huawei]).map((a) => a.id), [huawei.id]);
      expect(withoutHcDuplicates([huawei, bosch]).map((a) => a.id), [huawei.id]);
    });

    test('zwei Zusammenfassungen: die längere Strecke bleibt', () {
      final a = _fahrt('hc:2026-10-18 15:30:00', '15:30', km: 20.4);
      final b = _fahrt('hc:2026-10-18 15:31:05', '15:31', km: 20.9);
      expect(withoutHcDuplicates([a, b]).map((x) => x.id), [b.id]);
    });

    test('Tracker-CSV und Bosch-FIT derselben Fahrt: eine', () {
      final r = withoutHcDuplicates([
        _fahrt('2026-10-18_153002.csv', '15:30', karte: true),
        _fahrt('bosch.fit', '15:31', karte: true),
      ]);
      expect(r, hasLength(1));
    });

    test('zwei Fahrten nacheinander bleiben zwei', () {
      expect(
        withoutHcDuplicates([_fahrt('a.fit', '08:00'), _fahrt('b.fit', '15:30')]),
        hasLength(2),
      );
    });
  });

  group('Einheit entfernen', () {
    setUp(() => SharedPreferences.setMockInitialValues({'fitness_enabled': false}));

    test('entfernt, zurückgeholt — und die doppelte springt ein', () async {
      final huawei = _fahrt('2026-10-18_153000_rad_hc.csv', '15:30', karte: true);
      final bosch = _fahrt('2026-10-18_153105_rad_hc.csv', '15:31');
      final c = ProviderContainer(overrides: [
        fitnessRepositoryProvider.overrideWithValue(
          _Repo(FitnessData(activities: [huawei, bosch])),
        ),
      ]);
      addTearDown(c.dispose);
      await c.read(fitnessOverridesProvider.future);
      List<String> ids() =>
          c.read(fitnessDataProvider).value!.activities.map((a) => a.id).toList();

      await c.read(fitnessDataProvider.future);
      expect(ids(), [huawei.id]);

      // Die Huawei-Fahrt ist die falsche — weg damit; die von Bosch bleibt.
      await c.read(fitnessOverridesProvider.notifier).setHidden(huawei.id, true);
      await Future<void>.delayed(Duration.zero);
      expect(ids(), [bosch.id]);

      await c.read(fitnessOverridesProvider.notifier).setHidden(huawei.id, false);
      await Future<void>.delayed(Duration.zero);
      expect(ids(), [huawei.id]);
    });

    test('die Liste geht mit in die Korrekturen in der Nextcloud', () {
      const o = FitnessOverrides(hidden: {'x.fit', 'hc:2026-10-18 15:30:00'});
      expect(FitnessOverrides.fromJson(o.toJson()).hidden, o.hidden);
      expect(o.isEmpty, isFalse);
    });
  });
}
