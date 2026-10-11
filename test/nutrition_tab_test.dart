import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_providers.dart';
import 'package:family_planner/features/fitness/fitness_repository.dart';
import 'package:family_planner/features/nutrition/nutrition_models.dart';
import 'package:family_planner/features/nutrition/nutrition_providers.dart';
import 'package:family_planner/features/nutrition/nutrition_repository.dart';
import 'package:family_planner/features/nutrition/nutrition_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fest extends NutritionController {
  _Fest(this.daten);
  final NutritionData daten;

  @override
  Future<NutritionData> build() async => daten;

  @override
  Future<String?> sync() async => null;
}

class _Fitness extends FitnessDataController {
  _Fitness(this.daten);
  final FitnessData daten;

  @override
  Future<FitnessData> build() async => daten;
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => SharedPreferences.setMockInitialValues({'fitness_kcal_goal': 2000}));

  testWidgets('zeigt Summe, Ziel und Einträge je Mahlzeit', (tester) async {
    const hafer = Food(id: '1', name: 'Haferflocken', brand: 'Kölln', kcal100: 370);
    final heute = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final daten = NutritionData(
      foods: {hafer.id: hafer},
      days: {
        heute: NutritionDay(date: heute).withEntries([
          hafer.portion(grams: 60, meal: Meal.fruehstueck, time: '08:15'),
          const MealEntry(
            time: '12:30',
            meal: Meal.mittag,
            name: 'Ein sehr langer Name für ein Mittagessen mit vielen Zutaten und Beilagen',
            grams: 450,
            kcal: 2100,
          ),
        ]),
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        nutritionProvider.overrideWith(() => _Fest(daten)),
        fitnessDataProvider.overrideWith(() => _Fitness(FitnessData(healthDays: [
              HealthDay(date: heute, totalCalories: 1800),
            ]))),
      ],
      child: const MaterialApp(home: Scaffold(body: NutritionTab())),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2322'), findsOneWidget);
    expect(find.text('1800 kcal'), findsOneWidget);
    expect(find.text('+522 kcal'), findsOneWidget);
    expect(find.text('/ 2000 kcal'), findsOneWidget);
    expect(find.text('322 kcal drüber'), findsOneWidget);
    expect(find.text('Haferflocken (Kölln)'), findsOneWidget);
    expect(find.text('222 kcal'), findsWidgets);
    expect(find.textContaining('Frühstück'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leerer Tag ohne Fehler', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nutritionProvider.overrideWith(() => _Fest(const NutritionData())),
        fitnessDataProvider.overrideWith(() => _Fitness(const FitnessData())),
      ],
      child: const MaterialApp(home: Scaffold(body: NutritionTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('0'), findsOneWidget);
    expect(find.text('noch 2000 kcal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
