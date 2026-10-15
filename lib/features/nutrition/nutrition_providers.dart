import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../fitness/fitness_settings.dart';
import 'nutrition_health_connect.dart';
import 'nutrition_models.dart';
import 'nutrition_repository.dart';
import 'off_client.dart';
import 'photo_estimate.dart';

final nutritionRepositoryProvider =
    Provider<NutritionRepository>((ref) => NutritionRepository());

final offClientProvider = Provider<OffClient>((ref) => OffClient());

final claudeSettingsProvider = Provider<ClaudeSettings>((ref) => ClaudeSettings());

final claudePhotoClientProvider =
    Provider<ClaudePhotoClient>((ref) => ClaudePhotoClient());

final nutritionHcProvider =
    Provider<NutritionHealthConnect>((ref) => NutritionHealthConnect());

final nutritionProvider =
    AsyncNotifierProvider<NutritionController, NutritionData>(NutritionController.new);

/// Das Ernährungstagebuch. Jede Änderung geht sofort in die Nextcloud; ohne Netz wird
/// sie vorgemerkt und beim nächsten Abgleich nachgeholt.
class NutritionController extends AsyncNotifier<NutritionData> {
  bool _ersterAbgleich = false;

  NutritionRepository get _repo => ref.read(nutritionRepositoryProvider);

  @override
  Future<NutritionData> build() async {
    final lokal = await ref.read(nutritionRepositoryProvider).load();
    if (!_ersterAbgleich) {
      _ersterAbgleich = true;
      // Nicht abwarten: Der lokale Stand reicht zum Anzeigen.
      Future.microtask(sync);
    }
    return lokal;
  }

  Future<NutritionData> _aktuell() async => state.value ?? await _repo.load();

  /// Gleicht mit der Nextcloud ab. Fehler lassen den lokalen Stand stehen.
  Future<String?> sync() async {
    final account = await ref.read(accountProvider.future);
    final folder = await ref.read(fitnessFolderProvider.future);
    if (account == null || folder.isEmpty) {
      return 'Keine Nextcloud oder kein Datenordner gewählt.';
    }
    try {
      final neu = await _repo.sync(
        account: account,
        fitnessFolder: folder,
        data: await _aktuell(),
      );
      await _repo.save(neu);
      state = AsyncData(neu);
      return null;
    } catch (e) {
      return 'Abgleich nicht möglich: $e';
    }
  }

  Future<void> _speichereTag(NutritionDay tag) async {
    final neu = await _repo.saveDay(
      account: await ref.read(accountProvider.future),
      fitnessFolder: await ref.read(fitnessFolderProvider.future),
      data: await _aktuell(),
      day: tag,
    );
    state = AsyncData(neu);
    // Spiegel nach Health Connect, falls eingeschaltet — ohne darauf zu warten.
    unawaited(ref.read(nutritionHcProvider).schreibeTag(tag));
  }

  /// Gibt die letzten [tage] Tage an Health Connect — nach dem Einschalten.
  Future<void> spiegelnNachHealthConnect({int tage = 7}) async {
    final daten = await _aktuell();
    final heute = DateTime.now();
    for (var i = 0; i < tage; i++) {
      final d = DateTime(heute.year, heute.month, heute.day - i);
      final key = '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final tag = daten.days[key];
      if (tag != null) await ref.read(nutritionHcProvider).schreibeTag(tag);
    }
  }

  /// Trägt ein Lebensmittel ein und merkt es sich für „Zuletzt gegessen".
  Future<void> add(String date, Food food, MealEntry entry) async {
    final daten = await _aktuell();
    if (daten.foods[food.id] == null || daten.foods[food.id]!.updated != food.updated) {
      state = AsyncData(await _repo.saveFood(
        account: await ref.read(accountProvider.future),
        fitnessFolder: await ref.read(fitnessFolderProvider.future),
        data: daten,
        food: food,
      ));
    }
    final tag = (await _aktuell()).day(date);
    await _speichereTag(tag.withEntries([...tag.entries, entry]));
  }

  /// Trägt mehrere Einträge auf einmal ein — etwa die Schätzung zu einem Foto.
  Future<void> addEntries(String date, List<MealEntry> entries) async {
    if (entries.isEmpty) return;
    final tag = (await _aktuell()).day(date);
    await _speichereTag(tag.withEntries([...tag.entries, ...entries]));
  }

  Future<void> remove(String date, MealEntry entry) async {
    final tag = (await _aktuell()).day(date);
    await _speichereTag(
      tag.withEntries([...tag.entries]..remove(entry)),
    );
  }

  Future<void> _speichereVorlagen(Map<String, MealTemplate> vorlagen) async {
    state = AsyncData(await _repo.saveTemplates(
      account: await ref.read(accountProvider.future),
      fitnessFolder: await ref.read(fitnessFolderProvider.future),
      data: (await _aktuell()).copyWith(templates: vorlagen),
    ));
  }

  /// Speichert die Einträge einer Mahlzeit als Vorlage. Gleicher Name ersetzt die
  /// bisherige — so lässt sich „Mein Frühstück" einfach neu speichern.
  Future<void> saveTemplate(String name, List<MealEntry> eintraege) async {
    final daten = await _aktuell();
    final bisher = daten.activeTemplates
        .where((t) => t.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    final jetzt = DateTime.now();
    final t = MealTemplate(
      id: bisher?.id ?? 'v${jetzt.microsecondsSinceEpoch}',
      name: name,
      items: eintraege,
      updated: jetzt,
    );
    await _speichereVorlagen({...daten.templates, t.id: t});
  }

  Future<void> deleteTemplate(MealTemplate t) async {
    final daten = await _aktuell();
    await _speichereVorlagen({
      ...daten.templates,
      t.id: MealTemplate(
        id: t.id,
        name: t.name,
        items: const [],
        updated: DateTime.now(),
        deleted: true,
      ),
    });
  }

  /// Trägt alle Lebensmittel einer Vorlage auf einmal ein.
  Future<void> applyTemplate(String date, Meal meal, MealTemplate t, String time) async {
    final tag = (await _aktuell()).day(date);
    await _speichereTag(tag.withEntries([...tag.entries, ...t.entriesFor(meal, time)]));
  }

  Future<void> setWater(String date, int ml) async {
    final tag = (await _aktuell()).day(date);
    await _speichereTag(tag.withWater(ml));
  }

  /// Ändert die Menge eines Eintrags; die Nährwerte wachsen im selben Verhältnis mit.
  Future<void> changeGrams(String date, MealEntry entry, double grams) async {
    if (entry.grams <= 0 || grams <= 0) return;
    final f = grams / entry.grams;
    double? mal(double? v) => v == null ? null : v * f;
    final neu = MealEntry(
      time: entry.time,
      meal: entry.meal,
      name: entry.name,
      grams: grams,
      kcal: entry.kcal * f,
      protein: mal(entry.protein),
      carbs: mal(entry.carbs),
      fat: mal(entry.fat),
      foodId: entry.foodId,
    );
    final tag = (await _aktuell()).day(date);
    final liste = [...tag.entries];
    final i = liste.indexOf(entry);
    if (i < 0) return;
    liste[i] = neu;
    await _speichereTag(tag.withEntries(liste));
  }
}
