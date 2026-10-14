import 'package:family_planner/features/fitness/fitness_providers.dart';
import 'package:family_planner/features/fitness/fitness_repository.dart';
import 'package:family_planner/features/fitness/fitness_screen.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/nutrition/nutrition_providers.dart';
import 'package:family_planner/features/nutrition/nutrition_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Fitness extends FitnessDataController {
  @override
  Future<FitnessData> build() async => const FitnessData(healthDays: [
        HealthDay(date: '2026-10-12', steps: 9000),
      ]);
}

class _Ernaehrung extends NutritionController {
  @override
  Future<NutritionData> build() async => const NutritionData();

  @override
  Future<String?> sync() async => null;
}

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));
  setUp(() => SharedPreferences.setMockInitialValues({
        'fitness_enabled': true,
        'fitness_folder': '/Fitness',
      }));

  testWidgets('der Pfeil-Wunsch öffnet direkt den Tab Ernährung', (tester) async {
    final container = ProviderContainer(overrides: [
      fitnessDataProvider.overrideWith(_Fitness.new),
      nutritionProvider.overrideWith(_Ernaehrung.new),
    ]);
    addTearDown(container.dispose);
    // Der Wunsch steht schon, bevor der Bereich aufgebaut wird — wie beim Sprung
    // aus der Navigation.
    container.read(fitnessTabRequestProvider.notifier).set(3);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: FitnessScreen()),
    ));
    await tester.pumpAndSettle();

    final tabs = DefaultTabController.of(tester.element(find.byType(TabBar)));
    expect(tabs.index, 3);
    expect(container.read(fitnessTabRequestProvider), isNull);
    expect(find.text('Gesundheit'), findsOneWidget);
    expect(find.text('Gegessen'), findsOneWidget);
  });
}
