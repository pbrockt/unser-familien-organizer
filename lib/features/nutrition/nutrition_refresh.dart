import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/nextcloud_account.dart';
import 'nutrition_repository.dart';
import 'off_client.dart';

/// Einmal pro Woche „Meine Lebensmittel" bei Open Food Facts auffrischen — für den
/// Hintergrund-Job. Hersteller ändern Rezepturen; die Liste soll das mitbekommen, ohne
/// dass man daran denken muss.
class NutritionWeeklyRefresh {
  NutritionWeeklyRefresh({NutritionRepository? repo, OffClient? off})
      : _repo = repo ?? NutritionRepository(),
        _off = off ?? OffClient();

  final NutritionRepository _repo;
  final OffClient _off;

  static const _lastKey = 'nutrition_refresh_last';
  static const abstand = Duration(days: 7);

  /// Gibt zurück, ob ein Durchlauf stattfand.
  Future<bool> runIfDue({
    required NextcloudAccount account,
    required String fitnessFolder,
    DateTime? now,
  }) async {
    if (fitnessFolder.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final jetzt = now ?? DateTime.now();
    final zuletzt = prefs.getInt(_lastKey);
    if (zuletzt != null &&
        jetzt.difference(DateTime.fromMillisecondsSinceEpoch(zuletzt)) < abstand) {
      return false;
    }
    final lokal = await _repo.load();
    // Wer noch nichts gegessen hat, hat auch nichts aufzufrischen.
    if (lokal.foods.isEmpty) return false;

    // Erst die Liste aus der Nextcloud holen: Ein anderes Gerät hat sie vielleicht
    // gerade erweitert.
    final aktuell = await _repo.sync(
      account: account,
      fitnessFolder: fitnessFolder,
      data: lokal,
    );
    await _repo.refreshFoods(
      account: account,
      fitnessFolder: fitnessFolder,
      data: aktuell,
      off: _off,
      now: jetzt,
    );
    await prefs.setInt(_lastKey, jetzt.millisecondsSinceEpoch);
    return true;
  }
}
