import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/features/fitness/fitness_webdav.dart';
import 'package:family_planner/features/fitness/health_connect_file.dart';
import 'package:family_planner/features/fitness/health_connect_mapping.dart';
import 'package:family_planner/features/fitness/health_connect_source.dart';
import 'package:family_planner/features/fitness/health_connect_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Health Connect mit festen Schritten für heute und die beiden Tage davor.
class _Quelle extends HealthConnectSource {
  _Quelle(this.schritte);
  final Map<String, int> schritte;

  @override
  Future<HcStatus> status() async => HcStatus.bereit;

  @override
  Future<HcAbruf> abrufen({required DateTime von, required DateTime bis}) async =>
      HcAbruf(
        samples: const [],
        workouts: const [],
        stepsPerDay: schritte,
        fehler: const {},
        hintergrund: true,
        verlauf: true,
      );
}

/// Nextcloud im Speicher.
class _Cloud extends WebDavClient {
  final dateien = <String, String>{};
  final geschrieben = <String>[];

  @override
  Future<void> ensureFolder(NextcloudAccount account, String folder) async {}

  @override
  Future<List<RemoteEntry>> list(NextcloudAccount account, String folder) async => [
        for (final p in dateien.keys)
          if (p.startsWith('$folder/'))
            RemoteEntry(path: p, name: p.split('/').last, isDirectory: false),
      ];

  @override
  Future<String> read(NextcloudAccount account, String path) async => dateien[path]!;

  @override
  Future<void> write(NextcloudAccount account, String path, String text) async {
    dateien[path] = text;
    geschrieben.add(path);
  }
}

void main() {
  const account = NextcloudAccount(
    baseUrl: 'https://cloud.example',
    username: 'phillipp',
    appPassword: 'x',
  );
  final heute = DateTime.now();
  final tag = dayKey(heute);
  final ordner = '/Fitness/$kHcFolderName';

  setUp(() => SharedPreferences.setMockInitialValues({
        HealthConnectSync.enabledKey: true,
      }));

  test('legt jeden Tag als Datei im Unterordner ab', () async {
    final cloud = _Cloud();
    final r = await HealthConnectSync(quelle: _Quelle({tag: 5000}), client: cloud)
        .runIfDue(account: account, fitnessFolder: '/Fitness', force: true);
    expect(r!.geschrieben, 1);
    expect(cloud.dateien['$ordner/$tag.md'], contains('steps: 5000'));
  });

  test('lädt nichts hoch, wenn sich nichts geändert hat', () async {
    final cloud = _Cloud();
    final sync = HealthConnectSync(quelle: _Quelle({tag: 5000}), client: cloud);
    await sync.runIfDue(account: account, fitnessFolder: '/Fitness', force: true);
    final r = await sync.runIfDue(account: account, fitnessFolder: '/Fitness', force: true);
    expect(r!.unveraendert, 1);
    expect(cloud.geschrieben, hasLength(1));
  });

  test('aktualisiert den Tag, wenn neue Schritte dazukommen', () async {
    final cloud = _Cloud();
    await HealthConnectSync(quelle: _Quelle({tag: 5000}), client: cloud)
        .runIfDue(account: account, fitnessFolder: '/Fitness', force: true);
    await HealthConnectSync(quelle: _Quelle({tag: 7300}), client: cloud)
        .runIfDue(account: account, fitnessFolder: '/Fitness', force: true);
    expect(cloud.dateien['$ordner/$tag.md'], contains('steps: 7300'));
  });

  test('überschreibt einen von Hand geänderten Tag nicht', () async {
    final cloud = _Cloud();
    await HealthConnectSync(quelle: _Quelle({tag: 5000}), client: cloud)
        .runIfDue(account: account, fitnessFolder: '/Fitness', force: true);
    // In der Nextcloud von Hand korrigiert.
    cloud.dateien['$ordner/$tag.md'] =
        cloud.dateien['$ordner/$tag.md']!.replaceFirst('steps: 5000', 'steps: 6100');

    final r = await HealthConnectSync(quelle: _Quelle({tag: 7300}), client: cloud)
        .runIfDue(account: account, fitnessFolder: '/Fitness', force: true);
    expect(r!.geschuetzt, 1);
    expect(cloud.dateien['$ordner/$tag.md'], contains('steps: 6100'));
  });

  test('wartet 30 Minuten bis zum nächsten Abruf', () async {
    final cloud = _Cloud();
    final sync = HealthConnectSync(quelle: _Quelle({tag: 5000}), client: cloud);
    expect(await sync.runIfDue(account: account, fitnessFolder: '/Fitness'), isNotNull);
    expect(await sync.runIfDue(account: account, fitnessFolder: '/Fitness'), isNull);
  });

  test('tut nichts, solange es ausgeschaltet ist', () async {
    SharedPreferences.setMockInitialValues({});
    final cloud = _Cloud();
    final r = await HealthConnectSync(quelle: _Quelle({tag: 5000}), client: cloud)
        .runIfDue(account: account, fitnessFolder: '/Fitness', force: true);
    expect(r, isNull);
    expect(cloud.dateien, isEmpty);
  });

  test('Ersteinrichtung hört nach drei leeren Blöcken auf', () async {
    final cloud = _Cloud();
    final r = await HealthConnectSync(quelle: _Quelle({tag: 5000}), client: cloud)
        .runFullHistory(account: account, fitnessFolder: '/Fitness');
    // Der erste Block liefert den Tag, die nächsten drei nichts mehr.
    expect(r.geschrieben, 1);
  });
}
