import 'package:family_planner/features/nutrition/nutrition_health_connect.dart';
import 'package:family_planner/features/nutrition/nutrition_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

void main() {
  test('jeder Eintrag wird ein Datensatz mit Art, Zeit und Nährwerten', () {
    final tag = const NutritionDay(date: '2026-10-15').withEntries(const [
      MealEntry(
        time: '07:45',
        meal: Meal.fruehstueck,
        name: 'Haferflocken (Kölln)',
        grams: 60,
        kcal: 222,
        protein: 8.1,
        carbs: 35.2,
        fat: 4.2,
      ),
      // Von Hand in der Datei ergänzt, ohne Uhrzeit.
      MealEntry(time: '', meal: Meal.abend, name: 'Suppe', grams: 300, kcal: 180),
    ]);
    final r = mealRecordsFor(tag);
    expect(r, hasLength(2));
    expect(r[0].mealType, MealType.BREAKFAST);
    expect(r[0].start, DateTime(2026, 10, 15, 7, 45));
    expect(r[0].end.difference(r[0].start), const Duration(minutes: 1));
    expect(r[0].kcal, 222);
    expect(r[0].protein, 8.1);
    expect(r[0].name, 'Haferflocken (Kölln)');
    expect(r[1].mealType, MealType.DINNER);
    expect(r[1].start, DateTime(2026, 10, 15, 18));
  });

  test('ein leerer Tag ergibt nichts', () {
    expect(mealRecordsFor(const NutritionDay(date: '2026-10-15')), isEmpty);
  });
}
