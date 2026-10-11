import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/auth/nextcloud_account.dart';
import '../fitness/fitness_webdav.dart';
import 'nutrition_file.dart';
import 'nutrition_models.dart';
import 'nutrition_analysis.dart';
import 'off_client.dart';

/// Das Ernährungstagebuch, wie es die App vorhält.
class NutritionData {
  const NutritionData({
    this.days = const {},
    this.foods = const {},
    this.etags = const {},
    this.pendingDays = const {},
    this.foodsPending = false,
  });

  final Map<String, NutritionDay> days;
  final Map<String, Food> foods;

  /// Dateipfad → ETag beim letzten Lesen. Unveränderte Dateien werden nicht neu geladen.
  final Map<String, String> etags;

  /// Tage, die ohne Netz geändert wurden und noch hochmüssen.
  final Set<String> pendingDays;
  final bool foodsPending;

  NutritionDay day(String date) => days[date] ?? NutritionDay(date: date);

  /// Zuletzt gegessene Lebensmittel, jüngste zuerst, ohne Doppelte.
  List<Food> recentFoods({int max = 20}) {
    final out = <Food>[];
    final gesehen = <String>{};
    for (final key in days.keys.toList()..sort((a, b) => b.compareTo(a))) {
      for (final e in days[key]!.entries.reversed) {
        final f = e.foodId == null ? null : foods[e.foodId];
        if (f != null && gesehen.add(f.id)) out.add(f);
        if (out.length >= max) return out;
      }
    }
    return out;
  }

  NutritionData copyWith({
    Map<String, NutritionDay>? days,
    Map<String, Food>? foods,
    Map<String, String>? etags,
    Set<String>? pendingDays,
    bool? foodsPending,
  }) =>
      NutritionData(
        days: days ?? this.days,
        foods: foods ?? this.foods,
        etags: etags ?? this.etags,
        pendingDays: pendingDays ?? this.pendingDays,
        foodsPending: foodsPending ?? this.foodsPending,
      );

  Map<String, dynamic> toJson() => {
        'days': [for (final d in days.values) d.toJson()],
        'foods': [for (final f in foods.values) f.toJson()],
        'etags': etags,
        'pending': pendingDays.toList(),
        'foodsPending': foodsPending,
      };

  factory NutritionData.fromJson(Map<String, dynamic> j) => NutritionData(
        days: {
          for (final d in (j['days'] as List? ?? const []))
            (d as Map<String, dynamic>)['date'] as String: NutritionDay.fromJson(d),
        },
        foods: decodeFoods(j['foods']),
        etags: (j['etags'] as Map?)?.cast<String, String>() ?? const {},
        pendingDays: {...(j['pending'] as List? ?? const []).cast<String>()},
        foodsPending: j['foodsPending'] == true,
      );
}

Map<String, Food> decodeFoods(Object? raw) {
  final out = <String, Food>{};
  if (raw is! List) return out;
  for (final f in raw) {
    try {
      final food = Food.fromJson(f as Map<String, dynamic>);
      out[food.id] = food;
    } catch (_) {
      // Ein kaputter Eintrag soll nicht die ganze Liste kosten.
    }
  }
  return out;
}

/// Ein frisch abgefragtes Lebensmittel unter der bisherigen Kennung — so bleiben die
/// Verweise aus den Tagen gültig.
Food foodFromOffFresh(Food neu, String id, DateTime jetzt) => Food(
      id: id,
      name: neu.name,
      brand: neu.brand,
      barcode: neu.barcode,
      kcal100: neu.kcal100,
      protein100: neu.protein100,
      carbs100: neu.carbs100,
      fat100: neu.fat100,
      sugar100: neu.sugar100,
      portionG: neu.portionG,
      source: 'off',
      updated: jetzt,
    );

/// Führt zwei Lebensmittel-Listen zusammen; je Lebensmittel gewinnt der jüngere Stand.
Map<String, Food> mergeFoods(Map<String, Food> a, Map<String, Food> b) {
  final out = {...a};
  b.forEach((id, f) {
    final alt = out[id];
    final altZeit = alt?.updated ?? DateTime(2000);
    final neuZeit = f.updated ?? DateTime(2000);
    if (alt == null || !neuZeit.isBefore(altZeit)) out[id] = f;
  });
  return out;
}

/// Liest und schreibt das Tagebuch: lokal als Zwischenstand, in der Nextcloud als
/// eigentliche Ablage unter `<Fitness-Ordner>/Ernährung/`.
class NutritionRepository {
  NutritionRepository({WebDavClient? client}) : _client = client ?? const WebDavClient();

  final WebDavClient _client;

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'nutrition.json'));
  }

  Future<NutritionData> load() async {
    try {
      final f = await _cacheFile();
      if (!f.existsSync()) return const NutritionData();
      return NutritionData.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return const NutritionData();
    }
  }

  Future<void> save(NutritionData d) async {
    try {
      await (await _cacheFile()).writeAsString(jsonEncode(d.toJson()));
    } catch (_) {
      // Entbehrlich — die Nextcloud hat den Stand.
    }
  }

  static String folderOf(String fitnessFolder) {
    final f = fitnessFolder.endsWith('/')
        ? fitnessFolder.substring(0, fitnessFolder.length - 1)
        : fitnessFolder;
    return '$f/$kNutritionFolderName';
  }

  /// Lädt erst hoch, was offline liegen geblieben ist, und liest dann, was sich in der
  /// Nextcloud geändert hat — auch von Hand geänderte Tage.
  Future<NutritionData> sync({
    required NextcloudAccount account,
    required String fitnessFolder,
    required NutritionData data,
  }) async {
    final ordner = folderOf(fitnessFolder);
    await _client.ensureFolder(account, ordner);

    var d = data;
    for (final datum in d.pendingDays.toList()) {
      await _client.write(account, '$ordner/$datum.md', nutritionDayToMarkdown(d.day(datum)));
      d = d.copyWith(pendingDays: {...d.pendingDays}..remove(datum));
    }
    if (d.foodsPending) {
      await _writeFoods(account, ordner, d.foods);
      d = d.copyWith(foodsPending: false);
    }

    final etags = {...d.etags};
    final days = {...d.days};
    var foods = d.foods;
    for (final e in await _client.list(account, ordner)) {
      if (e.isDirectory) continue;
      final kennung = e.etag ?? 'size:${e.size}';
      if (etags[e.path] == kennung) continue;
      final name = e.name.toLowerCase();
      if (name == kFoodsFileName) {
        try {
          final roh = jsonDecode(await _client.read(account, e.path));
          foods = mergeFoods(foods, decodeFoods(roh is Map ? roh['foods'] : roh));
          etags[e.path] = kennung;
        } catch (_) {}
      } else if (name.endsWith('.md')) {
        final tag = nutritionDayFromMarkdown(await _client.read(account, e.path), e.name);
        if (tag != null) days[tag.date] = tag;
        etags[e.path] = kennung;
      }
    }
    return d.copyWith(days: days, foods: foods, etags: etags);
  }

  /// Schreibt einen Tag sofort. Klappt das nicht, bleibt er vorgemerkt.
  Future<NutritionData> saveDay({
    required NextcloudAccount? account,
    required String fitnessFolder,
    required NutritionData data,
    required NutritionDay day,
  }) async {
    var d = data.copyWith(days: {...data.days, day.date: day});
    try {
      if (account == null || fitnessFolder.isEmpty) throw StateError('offline');
      final ordner = folderOf(fitnessFolder);
      await _client.ensureFolder(account, ordner);
      await _client.write(account, '$ordner/${day.date}.md', nutritionDayToMarkdown(day));
      d = d.copyWith(pendingDays: {...d.pendingDays}..remove(day.date));
    } catch (_) {
      d = d.copyWith(pendingDays: {...d.pendingDays, day.date});
    }
    await save(d);
    return d;
  }

  /// Merkt sich ein Lebensmittel in „Meine Lebensmittel" und legt die Liste ab.
  Future<NutritionData> saveFood({
    required NextcloudAccount? account,
    required String fitnessFolder,
    required NutritionData data,
    required Food food,
  }) async {
    var d = data.copyWith(foods: {...data.foods, food.id: food});
    try {
      if (account == null || fitnessFolder.isEmpty) throw StateError('offline');
      await _writeFoods(account, folderOf(fitnessFolder), d.foods);
      d = d.copyWith(foodsPending: false);
    } catch (_) {
      d = d.copyWith(foodsPending: true);
    }
    await save(d);
    return d;
  }

  /// Fragt die fälligen Lebensmittel bei Open Food Facts neu ab und legt die Liste ab.
  ///
  /// Gilt nur für „Meine Lebensmittel" — die Einträge vergangener Tage tragen ihre
  /// Nährwerte selbst und bleiben, wie sie waren.
  Future<NutritionData> refreshFoods({
    required NextcloudAccount account,
    required String fitnessFolder,
    required NutritionData data,
    required OffClient off,
    DateTime? now,
  }) async {
    final jetzt = now ?? DateTime.now();
    final foods = {...data.foods};
    var geaendert = false;
    for (final alt in foodsToRefresh(foods, jetzt)) {
      try {
        final neu = await off.byBarcode(alt.barcode!);
        // Aus der Datenbank verschwunden: behalten, aber erst nächste Woche wieder fragen.
        foods[alt.id] = neu == null
            ? Food(
                id: alt.id,
                name: alt.name,
                brand: alt.brand,
                barcode: alt.barcode,
                kcal100: alt.kcal100,
                protein100: alt.protein100,
                carbs100: alt.carbs100,
                fat100: alt.fat100,
                sugar100: alt.sugar100,
                portionG: alt.portionG,
                source: alt.source,
                updated: jetzt,
              )
            : foodFromOffFresh(neu, alt.id, jetzt);
        geaendert = true;
      } on OffException {
        // Ausgelastet oder kein Netz: Rest beim nächsten Mal.
        break;
      }
    }
    if (!geaendert) return data;
    var d = data.copyWith(foods: foods);
    try {
      await _writeFoods(account, folderOf(fitnessFolder), foods);
    } catch (_) {
      d = d.copyWith(foodsPending: true);
    }
    await save(d);
    return d;
  }

  Future<void> _writeFoods(
    NextcloudAccount account,
    String ordner,
    Map<String, Food> foods,
  ) async {
    await _client.ensureFolder(account, ordner);
    const enc = JsonEncoder.withIndent(' ');
    await _client.write(
      account,
      '$ordner/$kFoodsFileName',
      enc.convert({
        'foods': [for (final f in foods.values) f.toJson()],
      }),
    );
  }
}
