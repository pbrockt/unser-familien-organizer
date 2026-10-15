import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform/platform_support.dart';
import 'nutrition_models.dart';

/// Ein Eintrag, wie er nach Health Connect geht.
class HcMealRecord {
  const HcMealRecord({
    required this.start,
    required this.end,
    required this.mealType,
    required this.name,
    required this.kcal,
    this.protein,
    this.carbs,
    this.fat,
  });

  final DateTime start;
  final DateTime end;
  final MealType mealType;
  final String name;
  final double kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
}

MealType _art(Meal m) => switch (m) {
      Meal.fruehstueck => MealType.BREAKFAST,
      Meal.mittag => MealType.LUNCH,
      Meal.abend => MealType.DINNER,
      Meal.snack => MealType.SNACK,
    };

/// Die Einträge eines Tages als Health-Connect-Datensätze. Ohne Uhrzeit (von Hand in der
/// Datei ergänzt) gilt die übliche Zeit der Mahlzeit, damit Yazio sie richtig einsortiert.
List<HcMealRecord> mealRecordsFor(NutritionDay tag) {
  final d = DateTime.tryParse(tag.date);
  if (d == null) return const [];
  const ueblich = {
    Meal.fruehstueck: 8,
    Meal.mittag: 12,
    Meal.abend: 18,
    Meal.snack: 15,
  };
  return [
    for (final e in tag.entries)
      () {
        final teile = e.time.split(':');
        final h = teile.length == 2 ? int.tryParse(teile[0]) : null;
        final m = teile.length == 2 ? int.tryParse(teile[1]) : null;
        final start = DateTime(d.year, d.month, d.day, h ?? ueblich[e.meal]!, m ?? 0);
        return HcMealRecord(
          start: start,
          end: start.add(const Duration(minutes: 1)),
          mealType: _art(e.meal),
          name: e.name,
          kcal: e.kcal,
          protein: e.protein,
          carbs: e.carbs,
          fat: e.fat,
        );
      }(),
  ];
}

/// Gibt das Ernährungstagebuch an Health Connect weiter, damit Yazio und andere Apps
/// sehen, was gegessen wurde.
///
/// Je Tag wird ersetzt statt ergänzt: Erst die eigenen Einträge des Tages löschen, dann
/// neu schreiben. Health Connect lässt eine App nur ihre eigenen Daten löschen — was Yazio
/// selbst einträgt, bleibt unberührt.
class NutritionHealthConnect {
  NutritionHealthConnect({Health? health}) : _health = health ?? Health();

  final Health _health;
  bool _konfiguriert = false;

  static const enabledKey = 'nutrition_hc_write';

  static Future<bool> isEnabled() async =>
      isAndroid && ((await SharedPreferences.getInstance()).getBool(enabledKey) ?? false);

  static Future<void> setEnabled(bool an) async =>
      (await SharedPreferences.getInstance()).setBool(enabledKey, an);

  Future<void> _konfigurieren() async {
    if (_konfiguriert) return;
    await _health.configure();
    _konfiguriert = true;
  }

  /// Fragt das Schreibrecht für Ernährung an.
  Future<bool> zugriffAnfragen() async {
    await _konfigurieren();
    return _health.requestAuthorization(
      const [HealthDataType.NUTRITION],
      permissions: const [HealthDataAccess.WRITE],
    );
  }

  /// Schreibt [tag] neu. Fehler werden geschluckt: Das Tagebuch in der Nextcloud ist die
  /// eigentliche Ablage, Health Connect nur ein Spiegel.
  Future<bool> schreibeTag(NutritionDay tag) async {
    if (!await isEnabled()) return false;
    final d = DateTime.tryParse(tag.date);
    if (d == null) return false;
    try {
      await _konfigurieren();
      await _health.delete(
        type: HealthDataType.NUTRITION,
        startTime: DateTime(d.year, d.month, d.day),
        endTime: DateTime(d.year, d.month, d.day, 23, 59, 59),
      );
      for (final r in mealRecordsFor(tag)) {
        await _health.writeMeal(
          mealType: r.mealType,
          startTime: r.start,
          endTime: r.end,
          name: r.name,
          caloriesConsumed: r.kcal,
          protein: r.protein,
          carbohydrates: r.carbs,
          fatTotal: r.fat,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
