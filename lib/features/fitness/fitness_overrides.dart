import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fitness_analysis.dart';
import 'fitness_models.dart';
import 'fitness_settings.dart';

/// Manuelle Angaben zu einer Einheit, je Datei: Sportart, Art der Einheit, E-Motor,
/// Zeiten.
///
/// Beides wird geschätzt, und Schätzungen liegen gelegentlich daneben. Wichtig ist, dass
/// eine Korrektur den Vorschlag *ersetzt* und nicht bloß überlagert: wählt man wieder den
/// Vorschlag, verschwindet die Festlegung, statt sie einzufrieren.
class FitnessOverrides {
  const FitnessOverrides({
    this.sports = const {},
    this.types = const {},
    this.ebikes = const {},
    this.times = const {},
  });

  final Map<String, Sport> sports;
  final Map<String, SessionType> types;

  /// Fahrten mit Motorunterstützung. Anders als Sportart und Art der Einheit lässt sich
  /// das aus den Messwerten nicht ablesen — ein Tritt am Berg sieht mit Motor aus wie
  /// ohne, nur schneller. Also gibt es hier keine Schätzung, die man korrigieren würde,
  /// sondern nur die Angabe selbst.
  final Set<String> ebikes;

  /// Von Hand korrigierte Gesamt- und Standzeit. Für den Fall, dass die Aufzeichnung
  /// danebenliegt: Gerät zu spät gestartet, vergessen zu stoppen, Pause nicht erkannt.
  final Map<String, TimeEdit> times;
}

/// Gesamt- und Standzeit einer Einheit, von Hand eingetragen. Die Fahrzeit ist der Rest —
/// drei Felder, von denen eines aus den anderen folgt, ließen sich sonst widersprüchlich
/// ausfüllen.
class TimeEdit {
  const TimeEdit({required this.totalSec, required this.stoppedSec});

  final int totalSec;
  final int stoppedSec;

  int get movingSec => (totalSec - stoppedSec).clamp(0, totalSec);

  @override
  bool operator ==(Object other) =>
      other is TimeEdit &&
      other.totalSec == totalSec &&
      other.stoppedSec == stoppedSec;

  @override
  int get hashCode => Object.hash(totalSec, stoppedSec);
}

/// Legt eine Zeitkorrektur über eine Einheit.
///
/// Alles, was an der Zeit hängt, zieht mit: Standanteil und Tempo in Bewegung. Das
/// Durchschnittstempo der Datei bleibt, weil es je nach Gerät anders gerechnet ist und
/// eine Korrektur der Pausen es nicht eindeutig verändert.
Activity applyTimeEdit(Activity a, TimeEdit e) {
  final total = e.totalSec < 0 ? 0 : e.totalSec;
  final moving = e.movingSec;
  return a.copyWith(
    durationSec: total,
    // Die Bewegungszeit 0 hieße im Modell „unbekannt" und fiele auf die Gesamtzeit
    // zurück. Wer von Hand „nur gestanden" einträgt, meint aber wirklich null — eine
    // Sekunde kommt dem am nächsten, ohne die Bedeutung umzudrehen.
    movingSec: total > 0 && moving == 0 ? 1 : moving,
    stoppedShare: total > 0 ? (total - moving) / total : 0.0,
    speedMovingAvgKmh: moving > 0 ? a.distanceKm / moving * 3600 : 0.0,
    timesEdited: true,
  );
}

/// Legt alle Zeitkorrekturen über die Einheiten; Einheiten ohne Korrektur bleiben, wie
/// sie sind.
List<Activity> applyTimeEdits(
  List<Activity> activities,
  Map<String, TimeEdit> edits,
) {
  if (edits.isEmpty) return activities;
  return [
    for (final a in activities)
      if (edits[a.id] case final e?) applyTimeEdit(a, e) else a,
  ];
}

final fitnessOverridesProvider =
    AsyncNotifierProvider<FitnessOverridesController, FitnessOverrides>(
  FitnessOverridesController.new,
);

class FitnessOverridesController extends AsyncNotifier<FitnessOverrides> {
  static const _sportKey = 'fitness_sport_overrides';
  static const _typeKey = 'fitness_type_overrides';
  static const _ebikeKey = 'fitness_ebike_ids';
  static const _timesKey = 'fitness_time_edits';

  @override
  Future<FitnessOverrides> build() async {
    final prefs = await SharedPreferences.getInstance();
    return FitnessOverrides(
      sports: _decode(prefs.getStringList(_sportKey), Sport.values),
      types: _decode(prefs.getStringList(_typeKey), SessionType.values),
      ebikes: (prefs.getStringList(_ebikeKey) ?? const []).toSet(),
      times: _decodeTimes(prefs.getStringList(_timesKey)),
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
      ebikes: state.value?.ebikes ?? const {},
      times: state.value?.times ?? const {},
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
      ebikes: state.value?.ebikes ?? const {},
      times: state.value?.times ?? const {},
    ));
  }

  Future<void> setEbike(String activityId, bool ebike) async {
    final prefs = await SharedPreferences.getInstance();
    final current = Set<String>.from(state.value?.ebikes ?? const <String>{});
    if (ebike) {
      current.add(activityId);
    } else {
      current.remove(activityId);
    }
    await prefs.setStringList(_ebikeKey, current.toList());
    state = AsyncData(FitnessOverrides(
      sports: state.value?.sports ?? const {},
      types: state.value?.types ?? const {},
      ebikes: current,
      times: state.value?.times ?? const {},
    ));
  }

  /// `null` nimmt die Korrektur zurück; dann gelten wieder die Zeiten aus der Datei.
  Future<void> setTimes(String activityId, TimeEdit? edit) async {
    final prefs = await SharedPreferences.getInstance();
    final current = Map<String, TimeEdit>.from(state.value?.times ?? const {});
    if (edit == null) {
      current.remove(activityId);
    } else {
      current[activityId] = edit;
    }
    await prefs.setStringList(_timesKey, [
      for (final e in current.entries)
        '${e.value.totalSec}\t${e.value.stoppedSec}\t${e.key}',
    ]);
    state = AsyncData(FitnessOverrides(
      sports: state.value?.sports ?? const {},
      types: state.value?.types ?? const {},
      ebikes: state.value?.ebikes ?? const {},
      times: current,
    ));
  }

  static Map<String, TimeEdit> _decodeTimes(List<String>? raw) {
    if (raw == null) return const {};
    final out = <String, TimeEdit>{};
    for (final line in raw) {
      final teile = line.split('\t');
      if (teile.length < 3) continue;
      final total = int.tryParse(teile[0]);
      final stand = int.tryParse(teile[1]);
      if (total == null || stand == null) continue;
      // Der Dateiname ist der Rest — falls er doch einmal einen Tabulator enthielte.
      out[teile.sublist(2).join('\t')] = TimeEdit(
        totalSec: total,
        stoppedSec: stand,
      );
    }
    return out;
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
  // Reihenfolge: manuelle Korrektur, dann die von der Begleitdatei genannte Sportart,
  // zuletzt die Schätzung aus den Messwerten.
  return o?.sports[activity.id] ?? activity.sportEffective;
});

/// Wurde diese Fahrt mit Motorunterstützung gemacht?
final ebikeProvider = Provider.family<bool, Activity>((ref, activity) {
  final o = ref.watch(fitnessOverridesProvider).value;
  return o?.ebikes.contains(activity.id) ?? false;
});

/// Die geltende Art einer Einheit: manuelle Wahl schlägt Schätzung.
final effectiveTypeProvider = Provider.family<SessionType, Activity>((ref, activity) {
  final o = ref.watch(fitnessOverridesProvider).value;
  final zones = ref.watch(fitnessZonesProvider);
  return o?.types[activity.id] ?? SessionClassifier.suggest(activity, zones);
});
