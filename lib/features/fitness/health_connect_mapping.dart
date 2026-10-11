import 'fitness_models.dart';

/// Was aus Health Connect gelesen wird — unabhängig vom Plugin, damit sich die
/// Umrechnung in Tageswerte ohne Gerät prüfen lässt.
enum HcKind {
  steps,
  heartRate,
  restingHr,
  spo2,
  weight,
  activeKcal,
  totalKcal,
  distance,
  sleepSession,
  sleepDeep,
  sleepLight,
  sleepRem,
  sleepAwake,
}

/// Lesbarer Name je Art, für die Test-Ansicht.
String hcKindLabel(HcKind k) => switch (k) {
      HcKind.steps => 'Schritte',
      HcKind.heartRate => 'Puls',
      HcKind.restingHr => 'Ruhepuls',
      HcKind.spo2 => 'Sauerstoff (SpO₂)',
      HcKind.weight => 'Gewicht',
      HcKind.activeKcal => 'Aktive Kalorien',
      HcKind.totalKcal => 'Kalorien gesamt',
      HcKind.distance => 'Distanz',
      HcKind.sleepSession => 'Schlaf',
      HcKind.sleepDeep => 'Tiefschlaf',
      HcKind.sleepLight => 'Leichtschlaf',
      HcKind.sleepRem => 'REM-Schlaf',
      HcKind.sleepAwake => 'Wach im Schlaf',
    };

/// Ein Messwert aus Health Connect. [value] in der Einheit, die die App führt: Schritte,
/// bpm, Prozent, kg, kcal, Meter. Bei Schlafphasen zählt nur der Zeitraum.
class HcSample {
  const HcSample({
    required this.kind,
    required this.from,
    required this.to,
    required this.value,
    required this.source,
  });

  final HcKind kind;
  final DateTime from;
  final DateTime to;
  final double value;

  /// App, die den Wert eingetragen hat (z. B. Huawei Health).
  final String source;
}

/// Eine Trainingseinheit, wie Health Connect sie kennt: nur die Zusammenfassung.
class HcWorkout {
  const HcWorkout({
    required this.from,
    required this.to,
    required this.type,
    required this.source,
    this.distanceM,
    this.kcal,
  });

  final DateTime from;
  final DateTime to;

  /// Art, wie Health Connect sie nennt (`BIKING`, `WALKING`, …).
  final String type;
  final String source;
  final double? distanceM;
  final double? kcal;

  int get minutes => to.difference(from).inMinutes;
}

String dayKey(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Die App mit den meisten Werten je Art.
///
/// Health Connect sammelt von allen Apps. Schreiben Huawei Health und der Schrittzähler
/// des Handys beide Schritte, ergäbe eine Summe über alle Quellen das Doppelte. Also
/// zählt je Art genau eine Quelle — die, die am meisten liefert.
Map<HcKind, String> dominantSources(List<HcSample> samples) {
  final counts = <HcKind, Map<String, int>>{};
  for (final s in samples) {
    final byKind = counts.putIfAbsent(s.kind, () => {});
    byKind[s.source] = (byKind[s.source] ?? 0) + 1;
  }
  return {
    for (final e in counts.entries)
      e.key: (e.value.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .first
          .key,
  };
}

/// Fasst die Rohwerte zu Tageswerten im selben Modell zusammen, das die `.md`-Dateien
/// liefern — so bleibt alles, was darauf aufbaut, unverändert.
///
/// [stepsPerDay] sind die von Health Connect selbst zusammengerechneten Schritte. Sie
/// gehen vor: Health Connect entfernt Doppelungen zwischen Quellen nach der Rangfolge,
/// die man dort eingestellt hat.
List<HealthDay> healthDaysFromHc({
  required List<HcSample> samples,
  List<HcWorkout> workouts = const [],
  Map<String, int> stepsPerDay = const {},
}) {
  final quelle = dominantSources(samples);
  final genutzt = [
    for (final s in samples)
      if (quelle[s.kind] == s.source) s,
  ];

  final tage = <String, _Tag>{};
  _Tag tag(String key) => tage.putIfAbsent(key, _Tag.new);

  stepsPerDay.forEach((k, v) {
    if (v > 0) tag(k).steps = v;
  });

  // Schlaf gehört zum Tag des Aufwachens: Die Nacht auf Dienstag ist Dienstags Schlaf.
  final sitzungen = genutzt.where((s) => s.kind == HcKind.sleepSession).toList()
    ..sort((a, b) => a.from.compareTo(b.from));
  String schlafTag(HcSample phase) {
    for (final s in sitzungen) {
      if (!phase.from.isBefore(s.from.subtract(const Duration(minutes: 1))) &&
          !phase.to.isAfter(s.to.add(const Duration(minutes: 1)))) {
        return dayKey(s.to);
      }
    }
    return dayKey(phase.to);
  }

  for (final s in genutzt) {
    final key = dayKey(s.from);
    switch (s.kind) {
      case HcKind.steps:
        // Nur, wenn Health Connect keine eigene Summe geliefert hat.
        if (!stepsPerDay.containsKey(key)) {
          tag(key).stepsSum += s.value;
        }
      case HcKind.heartRate:
        tag(key).hr.add(s.value);
      case HcKind.restingHr:
        tag(key).resting = s.value;
      case HcKind.spo2:
        tag(key).spo2.add(s.value);
      case HcKind.weight:
        tag(key).weight = s.value;
      case HcKind.activeKcal:
        tag(key).activeKcal += s.value;
      case HcKind.totalKcal:
        tag(key).totalKcal += s.value;
      case HcKind.distance:
        tag(key).distanceM += s.value;
      case HcKind.sleepSession:
        final t = tag(dayKey(s.to));
        t.sessionSec += s.to.difference(s.from).inSeconds;
        if (t.bed == null || s.from.isBefore(t.bed!)) t.bed = s.from;
        if (t.wake == null || s.to.isAfter(t.wake!)) t.wake = s.to;
      case HcKind.sleepDeep:
        tag(schlafTag(s)).deepSec += s.to.difference(s.from).inSeconds;
      case HcKind.sleepLight:
        tag(schlafTag(s)).lightSec += s.to.difference(s.from).inSeconds;
      case HcKind.sleepRem:
        tag(schlafTag(s)).remSec += s.to.difference(s.from).inSeconds;
      case HcKind.sleepAwake:
        tag(schlafTag(s)).awakeSec += s.to.difference(s.from).inSeconds;
    }
  }

  for (final w in workouts) {
    final t = tag(dayKey(w.from));
    t.workouts.add(w.type.toLowerCase());
    t.workoutMin += w.minutes;
    t.workoutKm += (w.distanceM ?? 0) / 1000;
  }

  double? stunden(int sec) => sec > 0 ? sec / 3600 : null;
  int? rund(double v) => v > 0 ? v.round() : null;

  final out = <HealthDay>[];
  for (final key in tage.keys.toList()..sort()) {
    final t = tage[key]!;
    // Mit Phasen ist Schlaf die Summe der Schlafphasen — die Sitzung enthält auch die
    // Wachphasen. Ohne Phasen bleibt nur die Sitzung selbst.
    final phasenSec = t.deepSec + t.lightSec + t.remSec;
    out.add(HealthDay(
      date: key,
      steps: t.steps ?? rund(t.stepsSum),
      sleepHours: stunden(phasenSec > 0 ? phasenSec : t.sessionSec - t.awakeSec),
      sleepDeepHours: stunden(t.deepSec),
      sleepCoreHours: stunden(t.lightSec),
      sleepRemHours: stunden(t.remSec),
      sleepAwakeHours: stunden(t.awakeSec),
      bedtime: t.bed == null ? null : _hhmm(t.bed!),
      wakeTime: t.wake == null ? null : _hhmm(t.wake!),
      activeCalories: rund(t.activeKcal),
      totalCalories: rund(t.totalKcal),
      hrAvg: t.hr.isEmpty
          ? null
          : (t.hr.reduce((a, b) => a + b) / t.hr.length).round(),
      hrMin: t.hr.isEmpty ? null : t.hr.reduce((a, b) => a < b ? a : b).round(),
      hrMax: t.hr.isEmpty ? null : t.hr.reduce((a, b) => a > b ? a : b).round(),
      restingHr: t.resting?.round(),
      spo2Avg: t.spo2.isEmpty
          ? null
          : (t.spo2.reduce((a, b) => a + b) / t.spo2.length).round(),
      spo2Min: t.spo2.isEmpty ? null : t.spo2.reduce((a, b) => a < b ? a : b).round(),
      weightKg: t.weight,
      walkingRunningKm: t.distanceM > 0 ? t.distanceM / 1000 : null,
      workoutCount: t.workouts.isEmpty ? null : t.workouts.length,
      workoutMinutes: t.workouts.isEmpty ? null : t.workoutMin,
      workoutDistanceKm: t.workoutKm > 0 ? t.workoutKm : null,
      workouts: t.workouts,
    ));
  }
  return out;
}

class _Tag {
  int? steps;
  double stepsSum = 0;
  final hr = <double>[];
  final spo2 = <double>[];
  double? resting;
  double? weight;
  double activeKcal = 0;
  double totalKcal = 0;
  double distanceM = 0;
  int sessionSec = 0;
  int deepSec = 0;
  int lightSec = 0;
  int remSec = 0;
  int awakeSec = 0;
  DateTime? bed;
  DateTime? wake;
  final workouts = <String>[];
  int workoutMin = 0;
  double workoutKm = 0;
}
