import 'package:health/health.dart';

import '../../core/platform/platform_support.dart';
import 'health_connect_mapping.dart';

enum HcStatus { nichtAndroid, nichtInstalliert, updateNoetig, bereit }

/// Ergebnis eines Abrufs — Rohwerte plus alles, was beim Prüfen hilft: wer was liefert
/// und was nicht gelesen werden durfte.
class HcAbruf {
  const HcAbruf({
    required this.samples,
    required this.workouts,
    required this.stepsPerDay,
    required this.fehler,
    required this.hintergrund,
    required this.verlauf,
  });

  final List<HcSample> samples;
  final List<HcWorkout> workouts;
  final Map<String, int> stepsPerDay;

  /// Art → Grund, warum sie nicht gelesen werden konnte.
  final Map<String, String> fehler;

  /// Darf die App im Hintergrund lesen? Voraussetzung für den späteren 30-Minuten-Abruf.
  final bool hintergrund;

  /// Darf die App mehr als die letzten 30 Tage lesen?
  final bool verlauf;
}

/// Liest aus Health Connect. Schreibt nichts hinein.
class HealthConnectSource {
  HealthConnectSource();

  final Health _health = Health();
  bool _konfiguriert = false;

  /// Was gelesen wird, und als was es in der App ankommt.
  static const Map<HealthDataType, HcKind> _arten = {
    HealthDataType.STEPS: HcKind.steps,
    HealthDataType.HEART_RATE: HcKind.heartRate,
    HealthDataType.RESTING_HEART_RATE: HcKind.restingHr,
    HealthDataType.BLOOD_OXYGEN: HcKind.spo2,
    HealthDataType.WEIGHT: HcKind.weight,
    HealthDataType.ACTIVE_ENERGY_BURNED: HcKind.activeKcal,
    HealthDataType.TOTAL_CALORIES_BURNED: HcKind.totalKcal,
    HealthDataType.DISTANCE_DELTA: HcKind.distance,
    HealthDataType.SLEEP_SESSION: HcKind.sleepSession,
    HealthDataType.SLEEP_DEEP: HcKind.sleepDeep,
    HealthDataType.SLEEP_LIGHT: HcKind.sleepLight,
    HealthDataType.SLEEP_REM: HcKind.sleepRem,
    HealthDataType.SLEEP_AWAKE: HcKind.sleepAwake,
  };

  static List<HealthDataType> get _alleTypen => [..._arten.keys, HealthDataType.WORKOUT];

  Future<void> _konfigurieren() async {
    if (_konfiguriert) return;
    await _health.configure();
    _konfiguriert = true;
  }

  Future<HcStatus> status() async {
    if (!isAndroid) return HcStatus.nichtAndroid;
    await _konfigurieren();
    return switch (await _health.getHealthConnectSdkStatus()) {
      HealthConnectSdkStatus.sdkAvailable => HcStatus.bereit,
      HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired =>
        HcStatus.updateNoetig,
      _ => HcStatus.nichtInstalliert,
    };
  }

  Future<void> installieren() async {
    await _konfigurieren();
    await _health.installHealthConnect();
  }

  /// Fragt die Leserechte an, dazu Verlauf und Hintergrund. Gibt zurück, ob die
  /// Grundrechte erteilt wurden; die beiden Zusätze darf man ablehnen.
  Future<bool> zugriffAnfragen() async {
    await _konfigurieren();
    final typen = _alleTypen;
    final ok = await _health.requestAuthorization(
      typen,
      permissions: [for (final _ in typen) HealthDataAccess.READ],
    );
    try {
      if (await _health.isHealthDataHistoryAvailable() &&
          !await _health.isHealthDataHistoryAuthorized()) {
        await _health.requestHealthDataHistoryAuthorization();
      }
      if (await _health.isHealthDataInBackgroundAvailable() &&
          !await _health.isHealthDataInBackgroundAuthorized()) {
        await _health.requestHealthDataInBackgroundAuthorization();
      }
    } catch (_) {
      // Ältere Health-Connect-Versionen kennen die Zusätze nicht — kein Grund, den
      // Grundzugriff scheitern zu lassen.
    }
    return ok;
  }

  Future<HcAbruf> abrufen({required DateTime von, required DateTime bis}) async {
    await _konfigurieren();
    final samples = <HcSample>[];
    final workouts = <HcWorkout>[];
    final fehler = <String, String>{};

    // Je Art einzeln: Fehlt eine einzelne Berechtigung, liefern die übrigen trotzdem.
    for (final e in _arten.entries) {
      try {
        final punkte = await _health.getHealthDataFromTypes(
          types: [e.key],
          startTime: von,
          endTime: bis,
        );
        for (final p in punkte) {
          final v = p.value;
          if (v is! NumericHealthValue) continue;
          var wert = v.numericValue.toDouble();
          // SpO₂ kommt je nach Version als Anteil (0,97) oder als Prozent (97).
          if (e.value == HcKind.spo2 && wert <= 1.0) wert *= 100;
          samples.add(HcSample(
            kind: e.value,
            from: p.dateFrom.toLocal(),
            to: p.dateTo.toLocal(),
            value: wert,
            source: p.sourceName.isNotEmpty ? p.sourceName : p.sourceId,
          ));
        }
      } catch (err) {
        fehler[hcKindLabel(e.value)] = '$err';
      }
    }

    try {
      final punkte = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: von,
        endTime: bis,
      );
      for (final p in punkte) {
        final v = p.value;
        if (v is! WorkoutHealthValue) continue;
        workouts.add(HcWorkout(
          from: p.dateFrom.toLocal(),
          to: p.dateTo.toLocal(),
          type: v.workoutActivityType.name,
          source: p.sourceName.isNotEmpty ? p.sourceName : p.sourceId,
          distanceM: v.totalDistance?.toDouble(),
          kcal: v.totalEnergyBurned?.toDouble(),
        ));
      }
    } catch (err) {
      fehler['Trainings'] = '$err';
    }

    // Schritte zusätzlich als Tagessumme von Health Connect selbst — ohne Doppelungen
    // zwischen Quellen.
    final stepsPerDay = <String, int>{};
    for (var tag = DateTime(von.year, von.month, von.day);
        tag.isBefore(bis);
        tag = DateTime(tag.year, tag.month, tag.day + 1)) {
      final ende = DateTime(tag.year, tag.month, tag.day + 1);
      try {
        final n = await _health.getTotalStepsInInterval(
          tag,
          ende.isAfter(bis) ? bis : ende,
        );
        if (n != null) stepsPerDay[dayKey(tag)] = n;
      } catch (_) {
        // Dann eben die Summe der dominanten Quelle.
      }
    }

    var hintergrund = false, verlauf = false;
    try {
      hintergrund = await _health.isHealthDataInBackgroundAuthorized();
      verlauf = await _health.isHealthDataHistoryAuthorized();
    } catch (_) {}

    return HcAbruf(
      samples: samples,
      workouts: workouts,
      stepsPerDay: stepsPerDay,
      fehler: fehler,
      hintergrund: hintergrund,
      verlauf: verlauf,
    );
  }
}
