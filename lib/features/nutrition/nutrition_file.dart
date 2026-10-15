import 'nutrition_models.dart';

/// Unterordner im Fitness-Ordner für das Ernährungstagebuch.
const String kNutritionFolderName = 'Ernährung';

/// Datei mit den Mahlzeiten-Vorlagen („Mein Frühstück").
const String kTemplatesFileName = 'vorlagen.json';

/// Datei mit den bekannten Lebensmitteln („Meine Lebensmittel").
const String kFoodsFileName = 'lebensmittel.json';

/// Schreibt einen Tag als `.md`: oben die Summen als Frontmatter, darunter je Eintrag eine
/// Zeile, die man lesen und von Hand ändern kann.
///
/// Maßgeblich sind die Zeilen, nicht die Summen — wer in der Nextcloud eine Zeile ändert
/// oder löscht, muss nicht nachrechnen.
String nutritionDayToMarkdown(NutritionDay d) {
  final out = <String>[
    '---',
    'date: ${d.date}',
    'kcal_eaten: ${d.kcal.round()}',
    'protein_g: ${d.protein.round()}',
    'carbs_g: ${d.carbs.round()}',
    'fat_g: ${d.fat.round()}',
    'eintraege: ${d.entries.length}',
    if (d.waterMl > 0) 'wasser_ml: ${d.waterMl}',
    'quelle: ernaehrung',
    '---',
    '',
    'Je Zeile: Uhrzeit | Mahlzeit | Lebensmittel | Menge | kcal | Eiweiß | Kohlenhydrate | '
        'Fett. Zeilen dürfen geändert oder gelöscht werden; die kcal zählen.',
  ];
  for (final m in Meal.values) {
    final liste = d.ofMeal(m);
    if (liste.isEmpty) continue;
    out
      ..add('')
      ..add('## ${mealLabel(m)}');
    for (final e in liste) {
      out.add(_zeile(e));
    }
  }
  out.add('');
  return out.join('\n');
}

String _zeile(MealEntry e) {
  final teile = <String>[
    e.time,
    mealLabel(e.meal),
    e.name.replaceAll('|', '/'),
    '${_zahl(e.grams)} g',
    '${e.kcal.round()} kcal',
    if (e.protein != null) 'E ${_zahl(e.protein!)}',
    if (e.carbs != null) 'K ${_zahl(e.carbs!)}',
    if (e.fat != null) 'F ${_zahl(e.fat!)}',
    if (e.foodId != null) '#${e.foodId}',
  ];
  return '- ${teile.join(' | ')}';
}

/// Liest einen Tag zurück. Gibt `null` zurück, wenn kein Datum zu finden ist.
///
/// Großzügig beim Lesen: Nach Uhrzeit, Mahlzeit und Name dürfen die übrigen Angaben in
/// beliebiger Reihenfolge stehen und auch fehlen — nur die kcal braucht jede Zeile.
NutritionDay? nutritionDayFromMarkdown(String text, String filename) {
  final norm = text.replaceAll('\r\n', '\n');
  final datum = RegExp(r'^date:\s*(\d{4}-\d{2}-\d{2})', multiLine: true)
          .firstMatch(norm)
          ?.group(1) ??
      RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(filename)?.group(1);
  if (datum == null) return null;

  final eintraege = <MealEntry>[];
  for (final roh in norm.split('\n')) {
    final z = roh.trim();
    if (!z.startsWith('- ')) continue;
    final e = _parseZeile(z.substring(2));
    if (e != null) eintraege.add(e);
  }
  final wasser = int.tryParse(
        RegExp(r'^wasser_ml:\s*(\d+)', multiLine: true).firstMatch(norm)?.group(1) ?? '',
      ) ??
      0;
  return NutritionDay(date: datum, waterMl: wasser).withEntries(eintraege);
}

MealEntry? _parseZeile(String z) {
  final teile = z.split('|').map((t) => t.trim()).toList();
  if (teile.length < 4) return null;
  final meal = mealFromLabel(teile[1]);
  if (meal == null) return null;
  final name = teile[2];
  if (name.isEmpty) return null;

  double? gramm, kcal, e, k, f;
  String? id;
  for (final t in teile.skip(3)) {
    final klein = t.toLowerCase();
    if (t.startsWith('#')) {
      id = t.substring(1).trim();
    } else if (klein.endsWith('kcal')) {
      kcal = _lies(klein.substring(0, klein.length - 4));
    } else if (klein.endsWith(' g') || RegExp(r'^\d+([.,]\d+)?g$').hasMatch(klein)) {
      gramm = _lies(klein.replaceAll('g', ''));
    } else if (klein.startsWith('e ')) {
      e = _lies(klein.substring(2));
    } else if (klein.startsWith('k ')) {
      k = _lies(klein.substring(2));
    } else if (klein.startsWith('f ')) {
      f = _lies(klein.substring(2));
    }
  }
  if (kcal == null) return null;
  return MealEntry(
    time: RegExp(r'^\d{1,2}:\d{2}$').hasMatch(teile[0]) ? teile[0] : '',
    meal: meal,
    name: name,
    grams: gramm ?? 0,
    kcal: kcal,
    protein: e,
    carbs: k,
    fat: f,
    foodId: id,
  );
}

double? _lies(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

/// Mit Komma und höchstens einer Nachkommastelle, ohne überflüssige Null: 60, 8,1.
String _zahl(double v) {
  final s = v.toStringAsFixed(1);
  return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s).replaceAll('.', ',');
}
