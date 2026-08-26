import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fitness_models.dart';

/// Schaltet den Fitness-Bereich frei. Aus, solange nichts eingerichtet ist — der
/// Familienplaner soll für alle anderen unverändert aussehen.
final fitnessEnabledProvider =
    AsyncNotifierProvider<FitnessEnabledController, bool>(
  FitnessEnabledController.new,
);

class FitnessEnabledController extends AsyncNotifier<bool> {
  static const _key = 'fitness_enabled';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> set(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    state = AsyncData(value);
  }
}

/// Ordner in der Nextcloud, in dem die .csv- und .md-Dateien liegen.
///
/// Pfad relativ zur WebDAV-Wurzel des Nutzers, z. B. `/Gesundheit`. Leer heißt: noch
/// nicht eingerichtet.
final fitnessFolderProvider =
    AsyncNotifierProvider<FitnessFolderController, String>(
  FitnessFolderController.new,
);

class FitnessFolderController extends AsyncNotifier<String> {
  static const _key = 'fitness_folder';

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? '';
  }

  Future<void> set(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value);
    state = AsyncData(value);
  }
}

/// Maximale Herzfrequenz. 0 = nicht hinterlegt, dann gelten die Standardzonen.
final fitnessMaxHrProvider = AsyncNotifierProvider<FitnessMaxHrController, int>(
  FitnessMaxHrController.new,
);

class FitnessMaxHrController extends AsyncNotifier<int> {
  static const _key = 'fitness_max_hr';

  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 0;
  }

  Future<void> set(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value.clamp(0, 240));
    state = AsyncData(value.clamp(0, 240));
  }
}

/// Tagesziel für die Schritte.
final fitnessStepGoalProvider =
    AsyncNotifierProvider<FitnessStepGoalController, int>(
  FitnessStepGoalController.new,
);

class FitnessStepGoalController extends AsyncNotifier<int> {
  static const _key = 'fitness_step_goal';

  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key) ?? 8000;
  }

  Future<void> set(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final v = value.clamp(1000, 50000);
    await prefs.setInt(_key, v);
    state = AsyncData(v);
  }
}

/// Die Pulszonen ergeben sich aus der eingestellten HFmax.
final fitnessZonesProvider = Provider<HrZones>((ref) {
  final maxHr = ref.watch(fitnessMaxHrProvider).value ?? 0;
  return HrZones.forMaxHr(maxHr > 0 ? maxHr : null);
});
