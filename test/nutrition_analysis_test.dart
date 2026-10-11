import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_webdav.dart';
import 'package:family_planner/features/nutrition/nutrition_analysis.dart';
import 'package:family_planner/features/nutrition/nutrition_models.dart';
import 'package:family_planner/features/nutrition/nutrition_repository.dart';
import 'package:family_planner/features/nutrition/off_client.dart';
import 'package:flutter_test/flutter_test.dart';

NutritionDay _tag(String d, double kcal) => NutritionDay(date: d).withEntries([
      MealEntry(
        time: '12:00',
        meal: Meal.mittag,
        name: 'Essen',
        grams: 100,
        kcal: kcal,
        protein: 50,
        carbs: 100,
        fat: 30,
      ),
    ]);

class _Off extends OffClient {
  _Off(this.antwort);
  final Map<String, Food?> antwort;
  final gefragt = <String>[];

  @override
  Future<Food?> byBarcode(String code) async {
    gefragt.add(code);
    if (!antwort.containsKey(code)) throw OffException('ausgelastet');
    return antwort[code];
  }
}

class _Cloud extends WebDavClient {
  final dateien = <String, String>{};
  @override
  Future<void> ensureFolder(NextcloudAccount account, String folder) async {}
  @override
  Future<void> write(NextcloudAccount account, String path, String text) async =>
      dateien[path] = text;
}

void main() {
  final heute = DateTime(2026, 10, 12, 13);

  group('Woche', () {
    test('Schnitt nur über erfasste Tage, heute bleibt außen vor', () {
      final w = weekSummary(
        data: NutritionData(days: {
          '2026-10-12': _tag('2026-10-12', 500), // heute — zählt nicht
          '2026-10-11': _tag('2026-10-11', 2000),
          '2026-10-09': _tag('2026-10-09', 2400),
          '2026-10-01': _tag('2026-10-01', 9999), // älter als 7 Tage
        }),
        health: const {},
        heute: heute,
      );
      expect(w.erfasst, 2);
      expect(w.avgEaten, 2200);
      expect(w.avgBurned, isNull);
      expect(w.avgBalance, isNull);
      expect(w.avgProtein, 50);
    });

    test('Bilanz nur an Tagen mit beiden Werten', () {
      final w = weekSummary(
        data: NutritionData(days: {
          '2026-10-11': _tag('2026-10-11', 2000),
          '2026-10-10': _tag('2026-10-10', 2600),
        }),
        health: const {
          '2026-10-11': HealthDay(date: '2026-10-11', totalCalories: 2500),
          '2026-10-09': HealthDay(date: '2026-10-09', totalCalories: 2300),
        },
        heute: heute,
      );
      expect(w.avgBurned, 2400);
      expect(w.mitBeidem, 1);
      expect(w.avgBalance, -500);
    });
  });

  group('Wöchentliche Auffrischung', () {
    final alt = Food(
      id: '4009249001102',
      barcode: '4009249001102',
      name: 'Kraft Klotz',
      kcal100: 210,
      updated: DateTime(2026, 9, 1),
    );
    final frisch = Food(
      id: '4013200254742',
      barcode: '4013200254742',
      name: 'Haferflocken',
      kcal100: 374,
      updated: DateTime(2026, 10, 10),
    );
    const eigen = Food(id: 'eigen:suppe', name: 'Suppe', kcal100: 60, source: 'eigen');
    final foods = {alt.id: alt, frisch.id: frisch, eigen.id: eigen};

    test('nur Open-Food-Facts-Produkte älter als eine Woche', () {
      expect(foodsToRefresh(foods, heute).map((f) => f.id), [alt.id]);
    });

    test('neue Nährwerte werden übernommen und die Liste abgelegt', () async {
      final cloud = _Cloud();
      final off = _Off({
        alt.barcode!: const Food(id: 'x', name: 'Kraft Klotz', kcal100: 214),
      });
      final d = await NutritionRepository(client: cloud).refreshFoods(
        account: const NextcloudAccount(baseUrl: 'https://c', username: 'u', appPassword: 'p'),
        fitnessFolder: '/Fitness',
        data: NutritionData(foods: foods),
        off: off,
        now: heute,
      );
      expect(off.gefragt, [alt.barcode]);
      // Kennung bleibt, damit die Verweise aus den Tagen gültig bleiben.
      expect(d.foods[alt.id]!.kcal100, 214);
      expect(d.foods[alt.id]!.updated, heute);
      expect(cloud.dateien.keys.single, endsWith('lebensmittel.json'));
    });

    test('ausgelastet: abbrechen und nichts verlieren', () async {
      final d = await NutritionRepository(client: _Cloud()).refreshFoods(
        account: const NextcloudAccount(baseUrl: 'https://c', username: 'u', appPassword: 'p'),
        fitnessFolder: '/Fitness',
        data: NutritionData(foods: foods),
        off: _Off(const {}),
        now: heute,
      );
      expect(d.foods[alt.id]!.kcal100, 210);
    });
  });
}
