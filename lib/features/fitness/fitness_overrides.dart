import 'dart:async';

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
    this.notEbikes = const {},
    this.times = const {},
  });

  final Map<String, Sport> sports;
  final Map<String, SessionType> types;

  /// Fahrten mit Motorunterstützung, von Hand angegeben. Aus den Messwerten lässt sich
  /// das nicht ablesen — ein Tritt am Berg sieht mit Motor aus wie ohne, nur schneller.
  /// Manche FIT-Dateien nennen es selbst (Sportart E-Bike); dann gilt die Datei, bis
  /// man widerspricht ([notEbikes]).
  final Set<String> ebikes;

  /// Von Hand korrigierte Gesamt- und Standzeit. Für den Fall, dass die Aufzeichnung
  /// danebenliegt: Gerät zu spät gestartet, vergessen zu stoppen, Pause nicht erkannt.
  final Map<String, TimeEdit> times;

  /// Fahrten, die die Datei als E-Bike nennt, die es laut Nutzer aber nicht waren.
  final Set<String> notEbikes;

  /// Mit Motor? Die eigene Angabe schlägt die der Datei, in beide Richtungen.
  bool isEbike(Activity a) {
    if (notEbikes.contains(a.id)) return false;
    return ebikes.contains(a.id) || a.ebikeDeclared;
  }

  bool get isEmpty =>
      sports.isEmpty &&
      types.isEmpty &&
      ebikes.isEmpty &&
      notEbikes.isEmpty &&
      times.isEmpty;

  FitnessOverrides copyWith({
    Map<String, Sport>? sports,
    Map<String, SessionType>? types,
    Set<String>? ebikes,
    Set<String>? notEbikes,
    Map<String, TimeEdit>? times,
  }) =>
      FitnessOverrides(
        sports: sports ?? this.sports,
        types: types ?? this.types,
        ebikes: ebikes ?? this.ebikes,
        notEbikes: notEbikes ?? this.notEbikes,
        times: times ?? this.times,
      );

  /// Für `korrekturen.json` in der Nextcloud — lesbar, damit man notfalls auch dort
  /// nachsehen kann, was korrigiert wurde.
  Map<String, dynamic> toJson() => {
        'sportart': {for (final e in sports.entries) e.key: e.value.name},
        'art': {for (final e in types.entries) e.key: e.value.name},
        'ebike': ebikes.toList()..sort(),
        'kein_ebike': notEbikes.toList()..sort(),
        'zeiten': {
          for (final e in times.entries)
            e.key: {'gesamt_s': e.value.totalSec, 'stand_s': e.value.stoppedSec},
        },
      };

  factory FitnessOverrides.fromJson(Map<String, dynamic> j) {
    Map<String, T> enums<T extends Enum>(Object? raw, List<T> values) {
      final out = <String, T>{};
      if (raw is! Map) return out;
      for (final e in raw.entries) {
        // Unbekannte Werte (etwa aus einer neueren App-Version) still übergehen.
        final v = values.where((v) => v.name == e.value).firstOrNull;
        if (v != null) out[e.key as String] = v;
      }
      return out;
    }
    Set<String> menge(Object? raw) =>
        raw is List ? {for (final v in raw) v.toString()} : <String>{};
    final zeiten = j['zeiten'];
    return FitnessOverrides(
      sports: enums(j['sportart'], Sport.values),
      types: enums(j['art'], SessionType.values),
      ebikes: menge(j['ebike']),
      notEbikes: menge(j['kein_ebike']),
      times: {
        if (zeiten is Map)
          for (final e in zeiten.entries)
            if (e.value is Map &&
                (e.value as Map)['gesamt_s'] is num &&
                (e.value as Map)['stand_s'] is num)
              e.key as String: TimeEdit(
                totalSec: ((e.value as Map)['gesamt_s'] as num).toInt(),
                stoppedSec: ((e.value as Map)['stand_s'] as num).toInt(),
              ),
      },
    );
  }
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
  static const _notEbikeKey = 'fitness_not_ebike_ids';
  static const _timesKey = 'fitness_time_edits';

  /// Zeitpunkt der letzten Änderung auf diesem Gerät — entscheidet beim Abgleich mit
  /// der Nextcloud, welcher Stand gilt.
  static const standKey = 'fitness_overrides_stand';

  @override
  Future<FitnessOverrides> build() async {
    final prefs = await SharedPreferences.getInstance();
    return FitnessOverrides(
      sports: _decode(prefs.getStringList(_sportKey), Sport.values),
      types: _decode(prefs.getStringList(_typeKey), SessionType.values),
      ebikes: (prefs.getStringList(_ebikeKey) ?? const []).toSet(),
      notEbikes: (prefs.getStringList(_notEbikeKey) ?? const []).toSet(),
      times: _decodeTimes(prefs.getStringList(_timesKey)),
    );
  }

  FitnessOverrides get _jetzt => state.value ?? const FitnessOverrides();

  /// Schreibt den ganzen Stand lokal und — ohne darauf zu warten — in die Nextcloud.
  Future<void> _speichern(FitnessOverrides neu) async {
    await _lokal(neu, DateTime.now());
    state = AsyncData(neu);
    final hochladen = onChanged;
    if (hochladen != null) unawaited(hochladen(neu));
  }

  Future<void> _lokal(FitnessOverrides o, DateTime stand) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_sportKey, _encode(o.sports));
    await prefs.setStringList(_typeKey, _encode(o.types));
    await prefs.setStringList(_ebikeKey, o.ebikes.toList());
    await prefs.setStringList(_notEbikeKey, o.notEbikes.toList());
    await prefs.setStringList(_timesKey, [
      for (final e in o.times.entries)
        '${e.value.totalSec}\t${e.value.stoppedSec}\t${e.key}',
    ]);
    await prefs.setInt(standKey, stand.millisecondsSinceEpoch);
  }

  /// Wird nach jeder Änderung aufgerufen — gesetzt vom Abgleich mit der Nextcloud.
  /// Bleibt hier ein Haken statt einer festen Abhängigkeit, damit der Controller ohne
  /// Konto und Netz testbar bleibt.
  Future<void> Function(FitnessOverrides)? onChanged;

  /// Übernimmt einen Stand aus der Nextcloud, ohne ihn gleich wieder hochzuladen.
  Future<void> replaceFromCloud(FitnessOverrides o, DateTime stand) async {
    await _lokal(o, stand);
    state = AsyncData(o);
  }

  Future<void> setSport(String activityId, Sport? sport) {
    final current = Map<String, Sport>.from(_jetzt.sports);
    if (sport == null) {
      current.remove(activityId);
    } else {
      current[activityId] = sport;
    }
    return _speichern(_jetzt.copyWith(sports: current));
  }

  Future<void> setType(String activityId, SessionType? type) {
    final current = Map<String, SessionType>.from(_jetzt.types);
    if (type == null) {
      current.remove(activityId);
    } else {
      current[activityId] = type;
    }
    return _speichern(_jetzt.copyWith(types: current));
  }

  /// [declared]: Die Datei selbst nennt die Fahrt ein E-Bike. Dann heißt „aus" eine
  /// ausdrückliche Gegenangabe, sonst stünde der Haken beim nächsten Laden wieder da.
  Future<void> setEbike(String activityId, bool ebike, {bool declared = false}) {
    final an = Set<String>.from(_jetzt.ebikes)..remove(activityId);
    final aus = Set<String>.from(_jetzt.notEbikes)..remove(activityId);
    if (ebike && !declared) an.add(activityId);
    if (!ebike && declared) aus.add(activityId);
    return _speichern(_jetzt.copyWith(ebikes: an, notEbikes: aus));
  }

  /// `null` nimmt die Korrektur zurück; dann gelten wieder die Zeiten aus der Datei.
  Future<void> setTimes(String activityId, TimeEdit? edit) {
    final current = Map<String, TimeEdit>.from(_jetzt.times);
    if (edit == null) {
      current.remove(activityId);
    } else {
      current[activityId] = edit;
    }
    return _speichern(_jetzt.copyWith(times: current));
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
  return o?.isEbike(activity) ?? activity.ebikeDeclared;
});

/// Die geltende Art einer Einheit: manuelle Wahl schlägt Schätzung.
final effectiveTypeProvider = Provider.family<SessionType, Activity>((ref, activity) {
  final o = ref.watch(fitnessOverridesProvider).value;
  final zones = ref.watch(fitnessZonesProvider);
  return o?.types[activity.id] ?? SessionClassifier.suggest(activity, zones);
});
