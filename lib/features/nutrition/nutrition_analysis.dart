import '../fitness/fitness_models.dart';
import 'nutrition_models.dart';
import 'nutrition_repository.dart';

/// Zusammenfassung mehrerer Tage.
class NutritionWeek {
  const NutritionWeek({
    required this.tage,
    required this.erfasst,
    this.avgEaten,
    this.avgBurned,
    this.avgBalance,
    this.mitBeidem = 0,
    this.avgProtein,
    this.avgCarbs,
    this.avgFat,
  });

  /// Betrachtete Tage.
  final int tage;

  /// Davon Tage mit mindestens einem Eintrag.
  final int erfasst;

  /// Ø gegessen — nur über erfasste Tage. Ein vergessener Tag ist kein Fastentag.
  final double? avgEaten;

  /// Ø verbraucht laut Health Connect, über die Tage, für die es Werte gibt.
  final double? avgBurned;

  /// Ø Bilanz (gegessen − verbraucht), nur über Tage, an denen beides vorliegt.
  final double? avgBalance;
  final int mitBeidem;

  final double? avgProtein;
  final double? avgCarbs;
  final double? avgFat;
}

/// Die letzten [tage] **abgeschlossenen** Tage vor [heute]. Heute bleibt außen vor: Am
/// Mittag sähe jede Woche nach Diät aus.
NutritionWeek weekSummary({
  required NutritionData data,
  required Map<String, HealthDay> health,
  required DateTime heute,
  int tage = 7,
}) {
  final daten = [
    for (var i = 1; i <= tage; i++)
      _key(DateTime(heute.year, heute.month, heute.day - i)),
  ];
  final gegessen = <NutritionDay>[
    for (final d in daten)
      if (data.days[d]?.entries.isNotEmpty ?? false) data.days[d]!,
  ];
  final verbraucht = <String, int>{
    for (final d in daten)
      if ((health[d]?.totalCalories ?? 0) > 0) d: health[d]!.totalCalories!,
  };
  final bilanz = <double>[
    for (final t in gegessen)
      if (verbraucht[t.date] != null) t.kcal - verbraucht[t.date]!,
  ];

  double? schnitt(Iterable<double> v) =>
      v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

  return NutritionWeek(
    tage: tage,
    erfasst: gegessen.length,
    avgEaten: schnitt(gegessen.map((t) => t.kcal)),
    avgBurned: schnitt(verbraucht.values.map((v) => v.toDouble())),
    avgBalance: schnitt(bilanz),
    mitBeidem: bilanz.length,
    avgProtein: schnitt(gegessen.map((t) => t.protein)),
    avgCarbs: schnitt(gegessen.map((t) => t.carbs)),
    avgFat: schnitt(gegessen.map((t) => t.fat)),
  );
}

String _key(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// Lebensmittel aus Open Food Facts, deren letzter Abgleich länger als [alter] her ist.
/// Höchstens [max] auf einmal — Open Food Facts soll nicht mit einem Schwall
/// Anfragen rechnen müssen; der Rest kommt beim nächsten Mal.
List<Food> foodsToRefresh(
  Map<String, Food> foods,
  DateTime jetzt, {
  Duration alter = const Duration(days: 7),
  int max = 40,
}) {
  final faellig = foods.values
      .where((f) =>
          f.source == 'off' &&
          f.barcode != null &&
          (f.updated == null || jetzt.difference(f.updated!) >= alter))
      .toList()
    ..sort((a, b) =>
        (a.updated ?? DateTime(2000)).compareTo(b.updated ?? DateTime(2000)));
  return faellig.take(max).toList();
}
