import 'package:family_planner/features/nutrition/nutrition_file.dart';
import 'package:family_planner/features/nutrition/nutrition_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _hafer = Food(
  id: '4009249001102',
  name: 'Haferflocken',
  brand: 'Kölln',
  kcal100: 370,
  protein100: 13.5,
  carbs100: 58.7,
  fat100: 7,
  portionG: 40,
);

void main() {
  group('Rechnung', () {
    test('Nährwerte wachsen mit der Menge', () {
      final e = _hafer.portion(grams: 60, meal: Meal.fruehstueck, time: '08:15');
      expect(e.kcal, closeTo(222, 0.01));
      expect(e.protein, closeTo(8.1, 0.01));
      expect(e.carbs, closeTo(35.22, 0.01));
      expect(e.fat, closeTo(4.2, 0.01));
      expect(e.name, 'Haferflocken (Kölln)');
    });

    test('Tagessummen über alle Mahlzeiten', () {
      final tag = const NutritionDay(date: '2026-10-11').withEntries([
        _hafer.portion(grams: 60, meal: Meal.fruehstueck, time: '08:15'),
        _hafer.portion(grams: 40, meal: Meal.snack, time: '16:00'),
      ]);
      expect(tag.kcal, closeTo(370, 0.01));
      expect(tag.ofMeal(Meal.snack), hasLength(1));
    });

    test('Mahlzeit nach Uhrzeit vorschlagen', () {
      expect(mealForTime(DateTime(2026, 1, 1, 7)), Meal.fruehstueck);
      expect(mealForTime(DateTime(2026, 1, 1, 12, 30)), Meal.mittag);
      expect(mealForTime(DateTime(2026, 1, 1, 19)), Meal.abend);
      expect(mealForTime(DateTime(2026, 1, 1, 15, 30)), Meal.snack);
    });
  });

  group('Tagesdatei', () {
    final tag = const NutritionDay(date: '2026-10-11').withEntries([
      _hafer.portion(grams: 60, meal: Meal.fruehstueck, time: '08:15'),
      const MealEntry(
        time: '12:40',
        meal: Meal.mittag,
        name: 'Spaghetti | Bolognese',
        grams: 350,
        kcal: 560,
      ),
    ]);

    test('schreiben und zurücklesen ergibt denselben Tag', () {
      final md = nutritionDayToMarkdown(tag);
      expect(md, contains('kcal_eaten: 782'));
      expect(md, contains('## Frühstück'));
      final z = nutritionDayFromMarkdown(md, '2026-10-11.md')!;
      expect(z.date, '2026-10-11');
      expect(z.entries, hasLength(2));
      expect(z.kcal, closeTo(782, 0.6));
      final f = z.entries.first;
      expect(f.meal, Meal.fruehstueck);
      expect(f.time, '08:15');
      expect(f.grams, 60);
      expect(f.protein, closeTo(8.1, 0.05));
      expect(f.foodId, '4009249001102');
      // Der Trenner im Namen darf die Zeile nicht zerlegen.
      expect(z.entries.last.name, 'Spaghetti / Bolognese');
    });

    test('von Hand geänderte und gelöschte Zeilen werden übernommen', () {
      final md = nutritionDayToMarkdown(tag)
          .replaceFirst('560 kcal', '600 kcal')
          .split('\n')
          .where((z) => !z.contains('Haferflocken'))
          .join('\n');
      final z = nutritionDayFromMarkdown(md, '2026-10-11.md')!;
      expect(z.entries, hasLength(1));
      expect(z.kcal, 600);
    });

    test('eine von Hand dazugeschriebene Zeile reicht mit Mahlzeit und kcal', () {
      final md = '${nutritionDayToMarkdown(tag)}- 21:00 | Snack | Apfel | 150 g | 78 kcal\n'
          '- Zwischendurch | Mittag | Kaffee mit Milch | 30 kcal\n';
      final z = nutritionDayFromMarkdown(md, '2026-10-11.md')!;
      expect(z.entries, hasLength(4));
      expect(z.ofMeal(Meal.snack).single.name, 'Apfel');
      final kaffee = z.ofMeal(Meal.mittag).firstWhere((e) => e.name == 'Kaffee mit Milch');
      expect(kaffee.kcal, 30);
      expect(kaffee.time, '');
    });

    test('Zeilen ohne kcal oder ohne bekannte Mahlzeit werden übersprungen', () {
      const md = '---\ndate: 2026-10-11\n---\n- 08:00 | Frühstück | Brot | 50 g\n'
          '- 09:00 | Brunch | Ei | 70 kcal\n';
      expect(nutritionDayFromMarkdown(md, 'x.md')!.entries, isEmpty);
    });
  });
}
