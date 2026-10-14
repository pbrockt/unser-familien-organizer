import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../fitness/fitness_settings.dart';
import 'nutrition_models.dart';
import 'nutrition_repository.dart';
import 'off_client.dart';

final nutritionRepositoryProvider =
    Provider<NutritionRepository>((ref) => NutritionRepository());

final offClientProvider = Provider<OffClient>((ref) => OffClient());

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

  Future<void> remove(String date, MealEntry entry) async {
    final tag = (await _aktuell()).day(date);
    await _speichereTag(
      tag.withEntries([...tag.entries]..remove(entry)),
    );
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
