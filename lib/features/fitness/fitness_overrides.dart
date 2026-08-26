import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fitness_analysis.dart';
import 'fitness_models.dart';
import 'fitness_settings.dart';

/// Manuelle Korrekturen von Sportart und Art der Einheit, je Datei.
///
/// Beides wird geschätzt, und Schätzungen liegen gelegentlich daneben. Wichtig ist, dass
/// eine Korrektur den Vorschlag *ersetzt* und nicht bloß überlagert: wählt man wieder den
/// Vorschlag, verschwindet die Festlegung, statt sie einzufrieren.
class FitnessOverrides {
  const FitnessOverrides({this.sports = const {}, this.types = const {}});

  final Map<String, Sport> sports;
  final Map<String, SessionType> types;
}

final fitnessOverridesProvider =
    AsyncNotifierProvider<FitnessOverridesController, FitnessOverrides>(
  FitnessOverridesController.new,
);

class FitnessOverridesController extends AsyncNotifier<FitnessOverrides> {
  static const _sportKey = 'fitness_sport_overrides';
  static const _typeKey = 'fitness_type_overrides';

  @override
  Future<FitnessOverrides> build() async {
    final prefs = await SharedPreferences.getInstance();
    return FitnessOverrides(
      sports: _decode(prefs.getStringList(_sportKey), Sport.values),
      types: _decode(prefs.getStringList(_typeKey), SessionType.values),
    );
  }

  Future<void> setSport(String activityId, Sport? sport) async {
    final prefs = await SharedPreferences.getInstance();
    final current = Map<String, Sport>.from(state.value?.sports ?? const {});
    if (sport == null) {
      current.remove(activityId);
    } else {
      current[activityId] = sport;
    }
    await prefs.setStringList(_sportKey, _encode(current));
    state = AsyncData(FitnessOverrides(
      sports: current,
      types: state.value?.types ?? const {},
    ));
  }

  Future<void> setType(String activityId, SessionType? type) async {
    final prefs = await SharedPreferences.getInstance();
    final current = Map<String, SessionType>.from(state.value?.types ?? const {});
    if (type == null) {
      current.remove(activityId);
    } else {
      current[activityId] = type;
    }
    await prefs.setStringList(_typeKey, _encode(current));
    state = AsyncData(FitnessOverrides(
      sports: state.value?.sports ?? const {},
      types: current,
    ));
  }

  // Ein Eintrag je Zeile als "wert\tdateiname". Dateinamen können alles Mögliche
  // enthalten, aber keinen Tabulator — damit ist die Trennung eindeutig.
  static List<String> _encode<T extends Enum>(Map<String, T> map) =>
      [for (final e in map.entries) '${e.value.name}\t${e.key}'];

  static Map<String, T> _decode<T extends Enum>(List<String>? raw, List<T> values) {
    if (raw == null) return const {};
    final out = <String, dynamic>{};
    for (final line in raw) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final name = line.substring(0, tab);
      final id = line.substring(tab + 1);
      for (final v in values) {
        if (v.name == name) {
          out[id] = v;
          break;
        }
      }
    }
    return out.cast<String, T>();
  }
}

/// Die geltende Sportart einer Einheit: manuelle Korrektur schlägt Erkennung.
final effectiveSportProvider = Provider.family<Sport, Activity>((ref, activity) {
  final o = ref.watch(fitnessOverridesProvider).value;
  return o?.sports[activity.id] ?? activity.sportDetected;
});

/// Die geltende Art einer Einheit: manuelle Wahl schlägt Schätzung.
final effectiveTypeProvider = Provider.family<SessionType, Activity>((ref, activity) {
  final o = ref.watch(fitnessOverridesProvider).value;
  final zones = ref.watch(fitnessZonesProvider);
  return o?.types[activity.id] ?? SessionClassifier.suggest(activity, zones);
});
