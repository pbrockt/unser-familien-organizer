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

  vorlagenTest();

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

class _MitVorlage extends NutritionController {
  NutritionData daten = NutritionData(templates: {
    'v1': MealTemplate(
      id: 'v1',
      name: 'Mein Frühstück',
      updated: DateTime(2026, 10, 15),
      items: const [
        MealEntry(time: '07:00', meal: Meal.fruehstueck, name: 'Müsli', grams: 80, kcal: 300),
        MealEntry(time: '07:00', meal: Meal.fruehstueck, name: 'Kaffee', grams: 250, kcal: 20),
      ],
    ),
  });

  @override
  Future<NutritionData> build() async => daten;

  @override
  Future<String?> sync() async => null;

  @override
  Future<void> applyTemplate(String date, Meal meal, MealTemplate t, String time) async {
    final tag = daten.day(date);
    daten = daten.copyWith(days: {
      date: tag.withEntries([...tag.entries, ...t.entriesFor(meal, time)]),
    });
    state = AsyncData(daten);
  }
}

void vorlagenTest() {
  testWidgets('Vorlage aus der Suche mit einem Tipp eintragen', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        nutritionProvider.overrideWith(_MitVorlage.new),
        fitnessDataProvider.overrideWith(() => _Fitness(const FitnessData())),
      ],
      child: const MaterialApp(home: Scaffold(body: NutritionTab())),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Frühstück hinzufügen'));
    await tester.pumpAndSettle();
    expect(find.text('MEINE VORLAGEN'), findsOneWidget);
    expect(find.text('2 Lebensmittel · 320 kcal'), findsOneWidget);

    await tester.tap(find.text('Mein Frühstück'));
    await tester.pumpAndSettle();
    expect(find.text('Müsli'), findsOneWidget);
    expect(find.text('Kaffee'), findsOneWidget);
    expect(find.text('320'), findsOneWidget);
    // Mit Einträgen gibt es das Menü zum Speichern als Vorlage.
    expect(find.byTooltip('Mehr'), findsOneWidget);
  });
}
