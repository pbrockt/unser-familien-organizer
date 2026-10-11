/// Mahlzeiten eines Tages, in der Reihenfolge, in der sie angezeigt werden.
enum Meal { fruehstueck, mittag, abend, snack }

String mealLabel(Meal m) => switch (m) {
      Meal.fruehstueck => 'Frühstück',
      Meal.mittag => 'Mittagessen',
      Meal.abend => 'Abendessen',
      Meal.snack => 'Snack',
    };

String mealIcon(Meal m) => switch (m) {
      Meal.fruehstueck => '🥣',
      Meal.mittag => '🍝',
      Meal.abend => '🍲',
      Meal.snack => '🍎',
    };

/// Erkennt eine Mahlzeit am Namen — so, wie er in der Tagesdatei steht. Wer die Datei von
/// Hand bearbeitet, schreibt vielleicht „Mittag" statt „Mittagessen".
Meal? mealFromLabel(String text) {
  final t = text.trim().toLowerCase();
  if (t.startsWith('früh') || t.startsWith('frueh')) return Meal.fruehstueck;
  if (t.startsWith('mittag')) return Meal.mittag;
  if (t.startsWith('abend')) return Meal.abend;
  if (t.startsWith('snack') || t.startsWith('zwischen')) return Meal.snack;
  return null;
}

/// Die vorgeschlagene Mahlzeit nach Uhrzeit — damit man sie meist nicht wählen muss.
Meal mealForTime(DateTime t) {
  if (t.hour < 10) return Meal.fruehstueck;
  if (t.hour < 15) return Meal.mittag;
  if (t.hour >= 17 && t.hour < 22) return Meal.abend;
  return Meal.snack;
}

/// Ein Lebensmittel mit Nährwerten je 100 g.
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.kcal100,
    this.brand,
    this.barcode,
    this.protein100,
    this.carbs100,
    this.fat100,
    this.sugar100,
    this.portionG,
    this.source = 'off',
    this.updated,
  });

  /// Barcode, wenn es einen gibt; sonst `eigen:<name>` für selbst angelegte.
  final String id;
  final String name;
  final String? brand;
  final String? barcode;
  final double kcal100;
  final double? protein100;
  final double? carbs100;
  final double? fat100;
  final double? sugar100;

  /// Übliche Portion in Gramm, falls bekannt.
  final double? portionG;

  /// `off` (Open Food Facts) oder `eigen` (von Hand angelegt).
  final String source;

  /// Zuletzt mit Open Food Facts abgeglichen.
  final DateTime? updated;

  String get label => brand == null || brand!.isEmpty ? name : '$name ($brand)';

  /// Nährwerte für [grams] Gramm.
  MealEntry portion({
    required double grams,
    required Meal meal,
    required String time,
  }) {
    double? anteil(double? je100) => je100 == null ? null : je100 * grams / 100;
    return MealEntry(
      time: time,
      meal: meal,
      name: label,
      grams: grams,
      kcal: kcal100 * grams / 100,
      protein: anteil(protein100),
      carbs: anteil(carbs100),
      fat: anteil(fat100),
      foodId: id,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (brand != null) 'brand': brand,
        if (barcode != null) 'barcode': barcode,
        'kcal': kcal100,
        if (protein100 != null) 'protein': protein100,
        if (carbs100 != null) 'carbs': carbs100,
        if (fat100 != null) 'fat': fat100,
        if (sugar100 != null) 'sugar': sugar100,
        if (portionG != null) 'portion': portionG,
        'source': source,
        if (updated != null) 'updated': updated!.toIso8601String(),
      };

  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: j['id'] as String,
        name: j['name'] as String,
        brand: j['brand'] as String?,
        barcode: j['barcode'] as String?,
        kcal100: (j['kcal'] as num).toDouble(),
        protein100: (j['protein'] as num?)?.toDouble(),
        carbs100: (j['carbs'] as num?)?.toDouble(),
        fat100: (j['fat'] as num?)?.toDouble(),
        sugar100: (j['sugar'] as num?)?.toDouble(),
        portionG: (j['portion'] as num?)?.toDouble(),
        source: j['source'] as String? ?? 'off',
        updated: DateTime.tryParse(j['updated'] as String? ?? ''),
      );
}

/// Ein Eintrag im Tagebuch: was, wie viel, wann.
///
/// Die Nährwerte werden beim Eintragen ausgerechnet und mitgespeichert. Ändert Open Food
/// Facts später die Angaben eines Produkts, bleibt der Tag, an dem man es gegessen hat,
/// trotzdem so, wie er war — und die Tagesdatei liest sich ohne Datenbank.
class MealEntry {
  const MealEntry({
    required this.time,
    required this.meal,
    required this.name,
    required this.grams,
    required this.kcal,
    this.protein,
    this.carbs,
    this.fat,
    this.foodId,
  });

  /// `HH:mm`.
  final String time;
  final Meal meal;
  final String name;
  final double grams;
  final double kcal;
  final double? protein;
  final double? carbs;
  final double? fat;
  final String? foodId;

  // Wertvergleich: Nach einem Abgleich sind es neue Objekte, gemeint ist aber derselbe
  // Eintrag — sonst ließe er sich nicht mehr löschen oder ändern.
  @override
  bool operator ==(Object other) =>
      other is MealEntry &&
      other.time == time &&
      other.meal == meal &&
      other.name == name &&
      other.grams == grams &&
      other.kcal == kcal &&
      other.foodId == foodId;

  @override
  int get hashCode => Object.hash(time, meal, name, grams, kcal, foodId);

  Map<String, dynamic> toJson() => {
        'time': time,
        'meal': meal.name,
        'name': name,
        'g': grams,
        'kcal': kcal,
        if (protein != null) 'p': protein,
        if (carbs != null) 'c': carbs,
        if (fat != null) 'f': fat,
        if (foodId != null) 'id': foodId,
      };

  factory MealEntry.fromJson(Map<String, dynamic> j) => MealEntry(
        time: j['time'] as String? ?? '',
        meal: Meal.values.firstWhere(
          (m) => m.name == j['meal'],
          orElse: () => Meal.snack,
        ),
        name: j['name'] as String,
        grams: (j['g'] as num).toDouble(),
        kcal: (j['kcal'] as num).toDouble(),
        protein: (j['p'] as num?)?.toDouble(),
        carbs: (j['c'] as num?)?.toDouble(),
        fat: (j['f'] as num?)?.toDouble(),
        foodId: j['id'] as String?,
      );
}

/// Alles, was an einem Tag gegessen wurde.
class NutritionDay {
  const NutritionDay({required this.date, this.entries = const []});

  /// yyyy-MM-dd.
  final String date;
  final List<MealEntry> entries;

  double get kcal => entries.fold(0, (s, e) => s + e.kcal);
  double get protein => entries.fold(0, (s, e) => s + (e.protein ?? 0));
  double get carbs => entries.fold(0, (s, e) => s + (e.carbs ?? 0));
  double get fat => entries.fold(0, (s, e) => s + (e.fat ?? 0));

  List<MealEntry> ofMeal(Meal m) => entries.where((e) => e.meal == m).toList();

  NutritionDay withEntries(List<MealEntry> neu) {
    final sortiert = [...neu]..sort((a, b) {
        final m = a.meal.index.compareTo(b.meal.index);
        return m != 0 ? m : a.time.compareTo(b.time);
      });
    return NutritionDay(date: date, entries: sortiert);
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory NutritionDay.fromJson(Map<String, dynamic> j) => NutritionDay(
        date: j['date'] as String,
        entries: (j['entries'] as List? ?? const [])
            .map((e) => MealEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
