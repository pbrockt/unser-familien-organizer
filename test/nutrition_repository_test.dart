import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/features/fitness/fitness_webdav.dart';
import 'package:family_planner/features/nutrition/nutrition_file.dart';
import 'package:family_planner/features/nutrition/nutrition_models.dart';
import 'package:family_planner/features/nutrition/nutrition_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Nextcloud im Speicher; jede geschriebene Datei bekommt einen neuen ETag.
class _Cloud extends WebDavClient {
  final dateien = <String, String>{};
  final etags = <String, String>{};
  var _zaehler = 0;
  bool offline = false;

  void setze(String pfad, String text) {
    dateien[pfad] = text;
    etags[pfad] = 'e${_zaehler++}';
  }

  @override
  Future<void> ensureFolder(NextcloudAccount account, String folder) async {
    if (offline) throw WebDavException('offline');
  }

  @override
  Future<List<RemoteEntry>> list(NextcloudAccount account, String folder) async => [
        for (final p in dateien.keys)
          if (p.startsWith('$folder/'))
            RemoteEntry(
              path: p,
              name: p.split('/').last,
              isDirectory: false,
              etag: etags[p],
            ),
      ];

  @override
  Future<String> read(NextcloudAccount account, String path) async => dateien[path]!;

  @override
  Future<void> write(NextcloudAccount account, String path, String text) async {
    if (offline) throw WebDavException('offline');
    setze(path, text);
  }
}

const _account = NextcloudAccount(
  baseUrl: 'https://cloud.example',
  username: 'phillipp',
  appPassword: 'x',
);

const _apfel = Food(id: 'eigen:apfel', name: 'Apfel', kcal100: 52, source: 'eigen');

void main() {
  const ordner = '/Fitness/$kNutritionFolderName';
  final tag = const NutritionDay(date: '2026-10-11').withEntries([
    _apfel.portion(grams: 150, meal: Meal.snack, time: '10:00'),
  ]);

  test('ein Tag landet sofort als Datei in der Nextcloud', () async {
    final cloud = _Cloud();
    final d = await NutritionRepository(client: cloud).saveDay(
      account: _account,
      fitnessFolder: '/Fitness',
      data: const NutritionData(),
      day: tag,
    );
    expect(cloud.dateien['$ordner/2026-10-11.md'], contains('Apfel'));
    expect(d.pendingDays, isEmpty);
  });

  test('ohne Netz vorgemerkt und beim Abgleich nachgeholt', () async {
    final cloud = _Cloud()..offline = true;
    final repo = NutritionRepository(client: cloud);
    var d = await repo.saveDay(
      account: _account,
      fitnessFolder: '/Fitness',
      data: const NutritionData(),
      day: tag,
    );
    expect(d.pendingDays, {'2026-10-11'});
    expect(cloud.dateien, isEmpty);

    cloud.offline = false;
    d = await repo.sync(account: _account, fitnessFolder: '/Fitness', data: d);
    expect(d.pendingDays, isEmpty);
    expect(cloud.dateien['$ordner/2026-10-11.md'], contains('Apfel'));
  });

  test('eine in der Nextcloud von Hand geänderte Datei wird übernommen', () async {
    final cloud = _Cloud();
    final repo = NutritionRepository(client: cloud);
    var d = await repo.saveDay(
      account: _account,
      fitnessFolder: '/Fitness',
      data: const NutritionData(),
      day: tag,
    );
    d = await repo.sync(account: _account, fitnessFolder: '/Fitness', data: d);

    cloud.setze(
      '$ordner/2026-10-11.md',
      cloud.dateien['$ordner/2026-10-11.md']!.replaceFirst('78 kcal', '95 kcal'),
    );
    d = await repo.sync(account: _account, fitnessFolder: '/Fitness', data: d);
    expect(d.day('2026-10-11').kcal, 95);
  });

  test('Tage von einem anderen Gerät kommen dazu', () async {
    final cloud = _Cloud()
      ..setze('$ordner/2026-10-10.md', nutritionDayToMarkdown(
        const NutritionDay(date: '2026-10-10').withEntries([
          _apfel.portion(grams: 100, meal: Meal.snack, time: '15:00'),
        ]),
      ));
    final d = await NutritionRepository(client: cloud)
        .sync(account: _account, fitnessFolder: '/Fitness', data: const NutritionData());
    expect(d.day('2026-10-10').kcal, 52);
  });

  test('Meine Lebensmittel: der jüngere Stand gewinnt', () {
    final alt = Food(id: '1', name: 'Alt', kcal100: 100, updated: DateTime(2026, 1, 1));
    final neu = Food(id: '1', name: 'Neu', kcal100: 120, updated: DateTime(2026, 6, 1));
    expect(mergeFoods({'1': alt}, {'1': neu})['1']!.name, 'Neu');
    expect(mergeFoods({'1': neu}, {'1': alt})['1']!.name, 'Neu');
  });

  test('Zuletzt gegessen: jüngste zuerst, ohne Doppelte', () {
    const birne = Food(id: 'eigen:birne', name: 'Birne', kcal100: 57, source: 'eigen');
    final d = NutritionData(
      foods: {_apfel.id: _apfel, birne.id: birne},
      days: {
        '2026-10-10': const NutritionDay(date: '2026-10-10').withEntries([
          birne.portion(grams: 100, meal: Meal.snack, time: '10:00'),
          _apfel.portion(grams: 100, meal: Meal.snack, time: '11:00'),
        ]),
        '2026-10-11': tag,
      },
    );
    expect(d.recentFoods().map((f) => f.name), ['Apfel', 'Birne']);
  });
}
