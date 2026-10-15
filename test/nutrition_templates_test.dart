import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/features/fitness/fitness_webdav.dart';
import 'package:family_planner/features/nutrition/nutrition_file.dart';
import 'package:family_planner/features/nutrition/nutrition_models.dart';
import 'package:family_planner/features/nutrition/nutrition_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _Cloud extends WebDavClient {
  final dateien = <String, String>{};
  final etags = <String, String>{};
  var _n = 0;
  bool offline = false;

  @override
  Future<void> ensureFolder(NextcloudAccount account, String folder) async {
    if (offline) throw WebDavException('offline');
  }

  @override
  Future<List<RemoteEntry>> list(NextcloudAccount account, String folder) async => [
        for (final p in dateien.keys)
          if (p.startsWith('$folder/'))
            RemoteEntry(path: p, name: p.split('/').last, isDirectory: false, etag: etags[p]),
      ];

  @override
  Future<String> read(NextcloudAccount account, String path) async => dateien[path]!;

  @override
  Future<void> write(NextcloudAccount account, String path, String text) async {
    if (offline) throw WebDavException('offline');
    dateien[path] = text;
    etags[path] = 'e${_n++}';
  }
}

const _account = NextcloudAccount(baseUrl: 'https://c', username: 'u', appPassword: 'p');
const _hafer = Food(id: '1', name: 'Haferflocken', kcal100: 370, protein100: 13.5);
const _milch = Food(id: '2', name: 'Milch', kcal100: 64, protein100: 3.4);

MealTemplate _fruehstueck({DateTime? am, bool weg = false}) => MealTemplate(
      id: 'v1',
      name: 'Mein Frühstück',
      updated: am ?? DateTime(2026, 10, 15, 7),
      deleted: weg,
      items: weg
          ? const []
          : [
              _hafer.portion(grams: 60, meal: Meal.fruehstueck, time: '07:00'),
              _milch.portion(grams: 200, meal: Meal.fruehstueck, time: '07:00'),
            ],
    );

void main() {
  test('eine Vorlage trägt alle Lebensmittel in die gewählte Mahlzeit ein', () {
    final e = _fruehstueck().entriesFor(Meal.snack, '16:10');
    expect(e, hasLength(2));
    expect(e.every((x) => x.meal == Meal.snack && x.time == '16:10'), isTrue);
    expect(e.fold<double>(0, (s, x) => s + x.kcal), closeTo(350, 0.01));
    expect(_fruehstueck().kcal, closeTo(350, 0.01));
  });

  test('Rundreise als JSON', () {
    final z = MealTemplate.fromJson(_fruehstueck().toJson());
    expect(z.name, 'Mein Frühstück');
    expect(z.items, _fruehstueck().items);
    expect(z.updated, DateTime(2026, 10, 15, 7));
  });

  test('der jüngere Stand gewinnt — auch eine Löschung', () {
    final alt = {'v1': _fruehstueck()};
    final geloescht = {'v1': _fruehstueck(am: DateTime(2026, 10, 15, 9), weg: true)};
    expect(mergeTemplates(alt, geloescht)['v1']!.deleted, isTrue);
    expect(mergeTemplates(geloescht, alt)['v1']!.deleted, isTrue);
    expect(NutritionData(templates: mergeTemplates(alt, geloescht)).activeTemplates, isEmpty);
  });

  test('in die Nextcloud und auf einem zweiten Gerät zurück', () async {
    final cloud = _Cloud();
    final repo = NutritionRepository(client: cloud);
    await repo.saveTemplates(
      account: _account,
      fitnessFolder: '/Fitness',
      data: NutritionData(templates: {'v1': _fruehstueck()}),
    );
    expect(cloud.dateien.keys.single, endsWith(kTemplatesFileName));

    final zweites = await repo.sync(
      account: _account,
      fitnessFolder: '/Fitness',
      data: const NutritionData(),
    );
    expect(zweites.activeTemplates.single.name, 'Mein Frühstück');
  });

  test('ohne Netz vorgemerkt und beim Abgleich nachgeholt', () async {
    final cloud = _Cloud()..offline = true;
    final repo = NutritionRepository(client: cloud);
    var d = await repo.saveTemplates(
      account: _account,
      fitnessFolder: '/Fitness',
      data: NutritionData(templates: {'v1': _fruehstueck()}),
    );
    expect(d.templatesPending, isTrue);
    cloud.offline = false;
    d = await repo.sync(account: _account, fitnessFolder: '/Fitness', data: d);
    expect(d.templatesPending, isFalse);
    expect(cloud.dateien.keys.single, endsWith(kTemplatesFileName));
  });
}
