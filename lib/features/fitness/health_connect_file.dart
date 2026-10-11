import 'dart:convert';

import 'fitness_models.dart';

/// Unterordner im Fitness-Ordner, in den die App die Tage aus Health Connect schreibt.
const String kHcFolderName = 'Health Connect';

/// Schreibt einen Tag als `.md` mit Frontmatter — dieselben Schlüssel, die der
/// [HealthParser] liest. Damit läuft der Tag durch denselben Import wie jede andere
/// Tagesdatei, und man kann ihn in der Nextcloud lesen und von Hand ändern.
///
/// Die Prüfsumme deckt alle Messwerte ab. Stimmt sie beim nächsten Abruf nicht mehr,
/// hat jemand die Datei geändert — dann bleibt sie, wie sie ist.
String healthDayToMarkdown(HealthDay d, {required DateTime stand}) {
  final werte = _werteZeilen(d);
  final st = stand.toLocal();
  return [
    '---',
    ...werte,
    'quelle: health_connect',
    'stand: ${_zweistellig(st.hour)}:${_zweistellig(st.minute)} '
        '${st.day}.${st.month}.${st.year}',
    'pruefsumme: ${_pruefsumme(werte)}',
    '---',
    '',
    'Automatisch aus Health Connect. Werte dürfen hier geändert werden — die App '
        'überschreibt diesen Tag danach nicht mehr.',
    '',
  ].join('\n');
}

/// Hat die App diese Datei selbst geschrieben, und ist sie seitdem unverändert?
///
/// Nur dann darf sie überschrieben werden. Fehlt die Prüfsumme oder passt sie nicht,
/// gilt die Datei als von Hand bearbeitet — im Zweifel lieber stehen lassen.
bool isUntouchedHcFile(String text) {
  final fm = _frontmatter(text);
  if (fm == null) return false;
  final summe = fm
      .where((z) => z.startsWith('pruefsumme:'))
      .map((z) => z.substring('pruefsumme:'.length).trim())
      .firstOrNull;
  if (summe == null || summe.isEmpty) return false;
  final werte = fm.where((z) => !_verwaltung.any(z.startsWith)).toList();
  return _pruefsumme(werte) == summe;
}

/// Ergäbe [neu] dieselben Messwerte wie die Datei [alt]? Dann braucht es kein
/// Hochladen — nur der Zeitstempel wäre anders.
bool sameMeasuredValues(String alt, HealthDay neu) {
  final fm = _frontmatter(alt);
  if (fm == null) return false;
  final werte = fm.where((z) => !_verwaltung.any(z.startsWith)).toList();
  return _pruefsumme(werte) == _pruefsumme(_werteZeilen(neu));
}

/// Führt zwei Tagesdateien desselben Datums zusammen: [vorrang] gewinnt, wo es einen
/// Wert hat, [rest] füllt die Lücken. So verliert ein Tag aus einer älteren Datei
/// nichts, was Health Connect nicht kennt — etwa Bewegungsminuten.
HealthDay mergeHealthDays(HealthDay vorrang, HealthDay rest) => HealthDay(
      date: vorrang.date,
      steps: vorrang.steps ?? rest.steps,
      sleepHours: vorrang.sleepHours ?? rest.sleepHours,
      activeCalories: vorrang.activeCalories ?? rest.activeCalories,
      totalCalories: vorrang.totalCalories ?? rest.totalCalories,
      hrAvg: vorrang.hrAvg ?? rest.hrAvg,
      hrMin: vorrang.hrMin ?? rest.hrMin,
      hrMax: vorrang.hrMax ?? rest.hrMax,
      spo2Avg: vorrang.spo2Avg ?? rest.spo2Avg,
      spo2Min: vorrang.spo2Min ?? rest.spo2Min,
      weightKg: vorrang.weightKg ?? rest.weightKg,
      restingHr: vorrang.restingHr ?? rest.restingHr,
      basalCalories: vorrang.basalCalories ?? rest.basalCalories,
      walkingRunningKm: vorrang.walkingRunningKm ?? rest.walkingRunningKm,
      exerciseMinutes: vorrang.exerciseMinutes ?? rest.exerciseMinutes,
      workoutCount: vorrang.workoutCount ?? rest.workoutCount,
      workoutMinutes: vorrang.workoutMinutes ?? rest.workoutMinutes,
      workoutDistanceKm: vorrang.workoutDistanceKm ?? rest.workoutDistanceKm,
      workoutAvgHr: vorrang.workoutAvgHr ?? rest.workoutAvgHr,
      workouts: vorrang.workouts.isNotEmpty ? vorrang.workouts : rest.workouts,
      sleepDeepHours: vorrang.sleepDeepHours ?? rest.sleepDeepHours,
      sleepRemHours: vorrang.sleepRemHours ?? rest.sleepRemHours,
      sleepCoreHours: vorrang.sleepCoreHours ?? rest.sleepCoreHours,
      sleepAwakeHours: vorrang.sleepAwakeHours ?? rest.sleepAwakeHours,
      bedtime: vorrang.bedtime ?? rest.bedtime,
      wakeTime: vorrang.wakeTime ?? rest.wakeTime,
      fromHealthConnect: vorrang.fromHealthConnect || rest.fromHealthConnect,
    );

/// Nimmt einen frisch gelesenen Tag in den Bestand auf. Ein Tag aus Health Connect
/// geht einem aus einer anderen Datei vor; sonst ersetzt der neue den alten.
HealthDay addHealthDay(HealthDay? vorhanden, HealthDay neu) {
  if (vorhanden == null) return neu;
  if (neu.fromHealthConnect) return mergeHealthDays(neu, vorhanden);
  if (vorhanden.fromHealthConnect) return mergeHealthDays(vorhanden, neu);
  return neu;
}

// Zeilen, die die App verwaltet und die nicht in die Prüfsumme gehören.
const _verwaltung = ['quelle:', 'stand:', 'pruefsumme:'];

List<String> _werteZeilen(HealthDay d) {
  String zahl(double v) {
    final s = v.toStringAsFixed(2);
    // 7.50 → 7.5, 81.00 → 81: kürzer zu lesen, und der Parser nimmt beides.
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  final z = <String>['date: ${d.date}'];
  void i(String k, int? v) {
    if (v != null) z.add('$k: $v');
  }

  void f(String k, double? v) {
    if (v != null) z.add('$k: ${zahl(v)}');
  }

  void t(String k, String? v) {
    if (v != null && v.isNotEmpty) z.add('$k: "$v"');
  }

  i('steps', d.steps);
  f('sleep_total_hours', d.sleepHours);
  f('sleep_deep_hours', d.sleepDeepHours);
  f('sleep_core_hours', d.sleepCoreHours);
  f('sleep_rem_hours', d.sleepRemHours);
  f('sleep_awake_hours', d.sleepAwakeHours);
  t('sleep_bedtime', d.bedtime);
  t('sleep_wake', d.wakeTime);
  i('active_calories', d.activeCalories);
  i('total_calories', d.totalCalories);
  i('average_heart_rate', d.hrAvg);
  i('heart_rate_min', d.hrMin);
  i('heart_rate_max', d.hrMax);
  i('resting_heart_rate', d.restingHr);
  i('blood_oxygen_avg', d.spo2Avg);
  i('blood_oxygen_min', d.spo2Min);
  f('weight_kg', d.weightKg);
  f('walking_running_km', d.walkingRunningKm);
  i('workout_count', d.workoutCount);
  i('workout_minutes', d.workoutMinutes);
  f('workout_distance_km', d.workoutDistanceKm);
  if (d.workouts.isNotEmpty) z.add('workouts: [${d.workouts.join(', ')}]');
  return z;
}

List<String>? _frontmatter(String text) {
  final m = RegExp(r'^---\s*\n(.*?)\n---', dotAll: true)
      .firstMatch(text.replaceAll('\r\n', '\n'));
  if (m == null) return null;
  return m
      .group(1)!
      .split('\n')
      .map((z) => z.trim())
      .where((z) => z.isNotEmpty)
      .toList();
}

/// FNV-1a über die Wertezeilen. Kein Schutz gegen Absicht — nur ein sicheres Zeichen,
/// ob jemand eine Zahl angefasst hat.
String _pruefsumme(List<String> zeilen) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(zeilen.join('\n'))) {
    h ^= b;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

String _zweistellig(int v) => v.toString().padLeft(2, '0');
