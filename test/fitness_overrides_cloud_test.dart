import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_overrides.dart';
import 'package:family_planner/features/fitness/fitness_overrides_cloud.dart';
import 'package:family_planner/features/fitness/fitness_webdav.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cloud extends WebDavClient {
  final dateien = <String, String>{};
  @override
  Future<String> read(NextcloudAccount account, String path) async {
    final t = dateien[path];
    if (t == null) throw WebDavException('Datei „$path" konnte nicht gelesen werden (404).');
    return t;
  }

  @override
  Future<void> write(NextcloudAccount account, String path, String text) async =>
      dateien[path] = text;
}

const _account = NextcloudAccount(baseUrl: 'https://c', username: 'u', appPassword: 'p');
const _pfad = '/Fitness/$kOverridesFileName';

const _korrekturen = FitnessOverrides(
  sports: {'a.csv': Sport.cycling},
  types: {'a.csv': SessionType.ausflug},
  ebikes: {'b.fit'},
  notEbikes: {'c.fit'},
  times: {'b.fit': TimeEdit(totalSec: 5238, stoppedSec: 1467)},
);

Activity _fahrt(String id, {bool ebike = false}) => Activity(
      id: id,
      date: '2026-10-14',
      timeOfDay: '15:00',
      sportDetected: Sport.cycling,
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
      ebikeDeclared: ebike,
    );

void main() {
  test('Datei-Rundreise verliert nichts', () {
    final z = FitnessOverrides.fromJson(_korrekturen.toJson());
    expect(z.sports, _korrekturen.sports);
    expect(z.types, _korrekturen.types);
    expect(z.ebikes, _korrekturen.ebikes);
    expect(z.notEbikes, _korrekturen.notEbikes);
    expect(z.times, _korrekturen.times);
  });

  group('Abgleich', () {
    test('erstes Mal: lokale Korrekturen werden hochgeladen', () async {
      final cloud = _Cloud();
      final r = await OverridesCloud(client: cloud).sync(
        account: _account,
        folder: '/Fitness',
        lokal: _korrekturen,
        lokalStand: DateTime(2026, 10, 14),
      );
      expect(r.hochgeladen, isTrue);
      expect(cloud.dateien[_pfad], contains('"a.csv": "cycling"'));
    });

    test('Neuinstallation: der Stand aus der Nextcloud kommt zurück', () async {
      final cloud = _Cloud();
      await OverridesCloud(client: cloud).upload(
        account: _account,
        folder: '/Fitness',
        overrides: _korrekturen,
        stand: DateTime(2026, 10, 14),
      );
      final r = await OverridesCloud(client: cloud).sync(
        account: _account,
        folder: '/Fitness',
        lokal: const FitnessOverrides(),
        lokalStand: null,
      );
      expect(r.uebernehmen!.times['b.fit']!.stoppedSec, 1467);
      expect(r.hochgeladen, isFalse);
    });

    test('jüngere Änderung auf dem Handy wird hochgeladen', () async {
      final cloud = _Cloud();
      final sync = OverridesCloud(client: cloud);
      await sync.upload(
        account: _account,
        folder: '/Fitness',
        overrides: _korrekturen,
        stand: DateTime(2026, 10, 1),
      );
      final neu = _korrekturen.copyWith(sports: {'a.csv': Sport.running});
      final r = await sync.sync(
        account: _account,
        folder: '/Fitness',
        lokal: neu,
        lokalStand: DateTime(2026, 10, 14),
      );
      expect(r.hochgeladen, isTrue);
      expect(r.uebernehmen, isNull);
      expect(cloud.dateien[_pfad], contains('"a.csv": "running"'));
    });

    test('jüngere Datei von einem anderen Gerät gewinnt', () async {
      final cloud = _Cloud();
      final sync = OverridesCloud(client: cloud);
      await sync.upload(
        account: _account,
        folder: '/Fitness',
        overrides: _korrekturen,
        stand: DateTime(2026, 10, 14),
      );
      final r = await sync.sync(
        account: _account,
        folder: '/Fitness',
        lokal: const FitnessOverrides(sports: {'x.csv': Sport.running}),
        lokalStand: DateTime(2026, 10, 1),
      );
      expect(r.uebernehmen!.sports, {'a.csv': Sport.cycling});
    });

    test('alte Korrekturen ohne Zeitstempel werden zusammengeführt, nicht verworfen',
        () async {
      final cloud = _Cloud();
      final sync = OverridesCloud(client: cloud);
      await sync.upload(
        account: _account,
        folder: '/Fitness',
        overrides: _korrekturen,
        stand: DateTime(2026, 10, 14),
      );
      final r = await sync.sync(
        account: _account,
        folder: '/Fitness',
        lokal: const FitnessOverrides(sports: {'alt.csv': Sport.running}),
        lokalStand: null,
      );
      expect(r.uebernehmen!.sports, {'a.csv': Sport.cycling, 'alt.csv': Sport.running});
      expect(r.hochgeladen, isTrue);
    });
  });

  group('⚡ aus der Datei', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('die Datei setzt den Haken, die eigene Angabe schlägt sie', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(fitnessOverridesProvider.future);
      final ctrl = c.read(fitnessOverridesProvider.notifier);
      final ebike = _fahrt('e.fit', ebike: true);
      final normal = _fahrt('n.fit');

      expect(c.read(fitnessOverridesProvider).value!.isEbike(ebike), isTrue);
      expect(c.read(fitnessOverridesProvider).value!.isEbike(normal), isFalse);

      await ctrl.setEbike(ebike.id, false, declared: true);
      expect(c.read(fitnessOverridesProvider).value!.isEbike(ebike), isFalse);
      await ctrl.setEbike(ebike.id, true, declared: true);
      expect(c.read(fitnessOverridesProvider).value!.isEbike(ebike), isTrue);
      expect(c.read(fitnessOverridesProvider).value!.notEbikes, isEmpty);

      await ctrl.setEbike(normal.id, true);
      expect(c.read(fitnessOverridesProvider).value!.isEbike(normal), isTrue);
    });

    test('jede Änderung meldet sich zum Hochladen und bekommt einen Zeitstempel', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(fitnessOverridesProvider.future);
      final ctrl = c.read(fitnessOverridesProvider.notifier);
      FitnessOverrides? gemeldet;
      ctrl.onChanged = (o) async => gemeldet = o;
      await ctrl.setSport('a.csv', Sport.running);
      expect(gemeldet?.sports['a.csv'], Sport.running);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(FitnessOverridesController.standKey), isNotNull);
    });
  });
}
