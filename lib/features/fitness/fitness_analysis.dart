import 'dart:math' as math;

import 'fitness_models.dart';

/// Erkennt die Sportart aus derselben CSV-Struktur, die der Tracker für Rad und Lauf
/// schreibt.
///
/// Der belastbarste Unterschied ist nicht die Geschwindigkeit (langsames Radfahren und
/// schnelles Laufen überlappen sich), sondern der zurückgelegte Weg pro Zyklus:
///
///   Rad:  Geschwindigkeit / Trittfrequenz   ~ 4–12 m pro Kurbelumdrehung (Entfaltung)
///   Lauf: Geschwindigkeit / Schrittfrequenz ~ 0,8–1,8 m pro Schritt (Schrittlänge)
///
/// Selbst wenn die Uhr die Laufkadenz pro Bein zählt (also ~85 statt ~170), landet der
/// Wert bei 1,6–3,6 m und bleibt damit unter der Rad-Spanne.
class SportDetector {
  const SportDetector._();

  /// Unterhalb dieser Meter-pro-Zyklus wird gelaufen, darüber gefahren.
  static const double _cycleLengthSplit = 4.0;

  /// Ab diesem Schnitt ist es praktisch sicher kein Laufen mehr.
  static const double _certainCyclingKmh = 22.0;

  static SportGuess detect(
      String filename, double avgSpeedKmh, int avgCadence) {
    final fromName = _fromFilename(filename);
    if (fromName != null) return SportGuess(fromName, 1.0);

    if (avgCadence > 0 && avgSpeedKmh > 0.5) {
      final metersPerCycle = (avgSpeedKmh / 3.6 * 60.0) / avgCadence;
      // Je weiter der Wert von der Trennlinie weg liegt, desto sicherer die Zuordnung.
      final distance = (metersPerCycle - _cycleLengthSplit).abs();
      final confidence = (0.55 + (distance / 4.0) * 0.45).clamp(0.55, 0.98);
      return SportGuess(
        metersPerCycle < _cycleLengthSplit ? Sport.running : Sport.cycling,
        confidence.toDouble(),
      );
    }

    // Ohne brauchbare Kadenz bleibt nur das Tempo — und das trennt nur an den Rändern.
    if (avgSpeedKmh >= _certainCyclingKmh) return const SportGuess(Sport.cycling, 0.8);
    if (avgSpeedKmh >= 0.5 && avgSpeedKmh <= 11.0) {
      return const SportGuess(Sport.running, 0.5);
    }
    return const SportGuess(Sport.unknown, 0);
  }

  static Sport? _fromFilename(String filename) {
    final n = filename.toLowerCase();
    const running = ['lauf', 'run', 'jog', 'joggen'];
    const cycling = ['rad', 'bike', 'cycl', 'velo', 'fahrrad'];
    if (running.any(n.contains)) return Sport.running;
    if (cycling.any(n.contains)) return Sport.cycling;
    return null;
  }
}

class SportGuess {
  const SportGuess(this.sport, this.confidence);
  final Sport sport;
  final double confidence;
}

enum Verdict { low, good, high, noData }

class CadenceCheck {
  const CadenceCheck(this.verdict, this.text,
      {this.perLeg = false, this.effectiveValue = 0});

  final Verdict verdict;
  final String text;

  /// true, wenn die Uhr die Laufkadenz offenbar pro Bein zählt (ca. 85 statt 170).
  final bool perLeg;

  /// Der zur Bewertung herangezogene Wert — bei [perLeg] also der verdoppelte.
  final int effectiveValue;
}

/// Bewertungen und Kennzahlen, die sich je Sportart unterscheiden.
class Analysis {
  const Analysis._();

  static CadenceCheck cadenceCheck(Sport sport, int cadence) {
    if (cadence <= 0) return const CadenceCheck(Verdict.noData, 'keine Daten');

    if (sport == Sport.running) {
      // Viele Uhren melden beim Laufen die Kadenz pro Bein. Werte unter 120 sind als
      // Schrittfrequenz unrealistisch niedrig — dann rechnen wir hoch.
      final perLeg = cadence < 120;
      final spm = perLeg ? cadence * 2 : cadence;
      final v = spm < 160
          ? Verdict.low
          : (spm <= 185 ? Verdict.good : Verdict.high);
      final text = switch (v) {
        Verdict.low => 'niedrig — kürzere, schnellere Schritte Richtung 170–180/min',
        Verdict.good => 'guter Bereich',
        _ => 'sehr hoch — Schrittlänge darf wieder wachsen',
      };
      return CadenceCheck(v, text, perLeg: perLeg, effectiveValue: spm);
    }

    final v = cadence < 70
        ? Verdict.low
        : (cadence <= 95 ? Verdict.good : Verdict.high);
    final text = switch (v) {
      Verdict.low => 'niedrig — Richtung 80–90/min treten',
      Verdict.good => 'guter Bereich',
      _ => 'sehr hoch — evtl. leichterer Gang',
    };
    return CadenceCheck(v, text, effectiveValue: cadence);
  }

  static String cadenceUnit(Sport sport) =>
      sport == Sport.running ? 'spm' : '/min';

  static String cadenceTargetLabel(Sport sport) => sport == Sport.running
      ? 'Zielbereich: 170–180 spm'
      : 'Zielbereich: 80–90/min';

  /// Referenzlinie fürs Kadenz-Diagramm.
  static double cadenceTarget(Sport sport) =>
      sport == Sport.running ? 175 : 85;

  static String formatPace(int secPerKm) {
    if (secPerKm <= 0) return '—';
    final m = secPerKm ~/ 60;
    final s = secPerKm % 60;
    return '$m:${s.toString().padLeft(2, '0')} min/km';
  }

  static String formatDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  static String formatElapsed(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class SessionClassifier {
  const SessionClassifier._();

  /// Schätzt die Art einer Einheit. Die Zonen kommen von außen herein, weil sie an der
  /// eingestellten HFmax hängen — deshalb passiert das hier und nicht beim Einlesen.
  static SessionType suggest(Activity activity, HrZones zones) {
    final hardShare = zones.hardSharePercent(activity.hrHistogram);

    // Viel Zeit oberhalb der zweiten Schwelle heißt harte Einheit, egal wie langsam das
    // Tempo dabei war (am Berg ist es niedrig und die Einheit trotzdem hart).
    if (hardShare >= 45) return SessionType.intensiv;

    // Ausflug: viele Standphasen UND durchgehend niedriger Puls. Nur eines von beidem
    // reicht nicht — Stadtverkehr hat auch viele Stopps, Grundlagentraining niedrigen Puls.
    final vielePausen = activity.stoppedShare > 0.20;
    final niedrigerPuls = activity.hrAvg > 0 && activity.hrAvg < zones.t1;
    if (vielePausen && niedrigerPuls) return SessionType.ausflug;

    return SessionType.training;
  }

  /// Belastungspunkte: Minuten je Pulszone, gewichtet nach Intensität.
  ///
  /// Damit werden eine lange lockere und eine kurze harte Einheit vergleichbar, und
  /// Radfahren lässt sich mit Laufen zusammenzählen. Bewusst eine grobe, nachvollziehbare
  /// Rechnung — keine Formel, die eine Genauigkeit vortäuscht, die die Daten nicht hergeben.
  static int loadScoreFromZones(List<int> zoneSeconds) {
    const weights = [1, 2, 3, 4];
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      sum += (zoneSeconds[i] / 60.0) * weights[i];
    }
    return sum.round();
  }

  static int loadScore(Activity activity, HrZones zones) =>
      loadScoreFromZones(zones.distribute(activity.hrHistogram));
}

/// Hinweise zu einer **einzelnen** Einheit — was war das für ein Training, und was
/// ließe sich beim nächsten Mal besser machen.
///
/// Die Bewertung richtet sich nach der Art der Einheit: einem Ausflug vorzuwerfen, er sei
/// zu langsam gewesen, wäre Unsinn, und einer Intervalleinheit, sie sei zu hart.
List<String> activityTips(
  Activity a,
  Sport sport,
  SessionType type,
  HrZones zones,
) {
  final out = <String>[];
  final hardShare = zones.hardSharePercent(a.hrHistogram);
  final zoneSeconds = zones.distribute(a.hrHistogram);
  final gesamt = zoneSeconds.fold<int>(0, (x, y) => x + y);
  final istLauf = sport == Sport.running;

  // 1) Charakter der Einheit einordnen.
  switch (type) {
    case SessionType.ausflug:
      out.add('Als Ausflug eingestuft: zählt bei Distanz und Belastung mit, bleibt aber '
          'aus den Leistungstrends heraus. Bewegung ist Bewegung.');
    case SessionType.intensiv:
      out.add('Harte Einheit — $hardShare % der Zeit über ${zones.t2} bpm. Nach so etwas '
          'braucht der Körper einen ruhigen Tag, sonst kommt der Effekt nicht an.');
    case SessionType.training:
      if (gesamt > 0 && zoneSeconds[0] + zoneSeconds[1] > gesamt * 0.8) {
        out.add('Schöne Grundlageneinheit: über 80 % der Zeit unter ${zones.t2} bpm. '
            'Genau davon lebt die Ausdauer.');
      } else {
        out.add('Gemischte Einheit — $hardShare % der Zeit im intensiven Bereich '
            'über ${zones.t2} bpm.');
      }
  }

  // 2) Kadenz, sofern gemessen.
  final cad = Analysis.cadenceCheck(sport, a.cadenceAvg);
  if (cad.verdict != Verdict.noData && type != SessionType.ausflug) {
    final einheit = Analysis.cadenceUnit(sport);
    out.add(switch (cad.verdict) {
      Verdict.good => 'Kadenz ${cad.effectiveValue} $einheit — guter Bereich.',
      _ => 'Kadenz ${cad.effectiveValue} $einheit — ${cad.text}.',
    });
  }

  // 3) Gleichmaessigkeit: springt der Puls stark, war die Einheit zerrissen.
  final pulse = a.series.where((p) => p.hr > 0).map((p) => p.hr.toDouble()).toList();
  if (pulse.length > 10 && type != SessionType.ausflug) {
    final schnitt = pulse.reduce((x, y) => x + y) / pulse.length;
    final abweichung = math.sqrt(
      pulse.map((v) => (v - schnitt) * (v - schnitt)).reduce((x, y) => x + y) /
          pulse.length,
    );
    if (abweichung > 18) {
      out.add('Der Puls schwankt stark (±${abweichung.round()} bpm). Bei Intervallen ist '
          'das gewollt — auf einer Grundlagenrunde deutet es auf Ampeln, Berge oder ein '
          'zu wechselhaftes Tempo hin.');
    } else if (abweichung < 8 && type == SessionType.training) {
      out.add('Sehr gleichmäßiger Puls (±${abweichung.round()} bpm) — sauber '
          'durchgezogen.');
    }
  }

  // 4) Standzeit.
  if (a.stoppedShare > 0.25 && type != SessionType.ausflug) {
    out.add('${(a.stoppedShare * 100).round()} % der Zeit standest du. Für eine '
        'Trainingswirkung ist eine Strecke ohne viele Stopps deutlich ergiebiger.');
  }

  // 5) Hoehenmeter ins Verhaeltnis setzen.
  if (a.distanceKm > 1 && a.elevGain > 0) {
    final proKm = a.elevGain / a.distanceKm;
    if (proKm > 15) {
      out.add('${proKm.round()} Höhenmeter pro Kilometer — hügelig. Ein niedrigerer '
          'Schnitt ist hier normal und kein Rückschritt.');
    }
  }

  // 6) Laenge einordnen.
  if (istLauf && a.distanceKm >= 10) {
    out.add('${a.distanceKm.toStringAsFixed(1)} km am Stück — das ist eine lange Einheit. '
        'Danach zählt vor allem, dass du wieder auftankst.');
  } else if (!istLauf && a.distanceKm >= 40) {
    out.add('${a.distanceKm.toStringAsFixed(1)} km — lange Ausfahrt. Solche Einheiten '
        'bauen die Grundlage, auf der alles andere steht.');
  }

  if (out.isEmpty) {
    out.add('Zu dieser Einheit gibt es nichts Auffälliges zu melden.');
  }
  return out;
}

/// Zusammenfassung über alle Einheiten einer Sportart.
class SportSummary {
  const SportSummary({
    required this.sport,
    required this.count,
    required this.totalKm,
    required this.totalSec,
    required this.avgHr,
    required this.avgCadence,
    required this.avgSpeedKmh,
    required this.avgPaceSecPerKm,
    required this.longest,
    required this.zoneSeconds,
    required this.hardSharePct,
    required this.speedTrend,
    required this.hrTrend,
    required this.cadenceTrend,
    required this.paceTrend,
    required this.loadScore,
    required this.excludedFromTrends,
    required this.trendBasis,
  });

  final Sport sport;
  final int count;
  final double totalKm;
  final int totalSec;
  final int avgHr;
  final int avgCadence;
  final double avgSpeedKmh;
  final int avgPaceSecPerKm;
  final Activity? longest;
  final List<int> zoneSeconds;
  final int hardSharePct;
  final double speedTrend;
  final double hrTrend;
  final double cadenceTrend;
  final double paceTrend;

  /// Summe der Belastungspunkte aller Einheiten — Ausflüge zählen hier mit.
  final int loadScore;

  /// Wie viele Einheiten als Ausflug gelten und deshalb aus den Trends fallen.
  final int excludedFromTrends;

  /// Wie viele Einheiten die Trends tatsächlich tragen.
  final int trendBasis;
}

class Summarizer {
  const Summarizer._();

  /// [typeOf] liefert die Art jeder Einheit. Ausflüge zählen in Summen und Belastung mit,
  /// fließen aber **nicht** in die Trends ein — sonst zieht eine gemütliche Familienrunde
  /// das Tempo nach unten und die App meldet einen Rückschritt, den es nicht gibt.
  static SportSummary? summarize(
    Sport sport,
    List<Activity> activities,
    HrZones zones, {
    SessionType Function(Activity)? typeOf,
  }) {
    if (activities.isEmpty) return null;
    final resolve = typeOf ?? (_) => SessionType.training;

    final sorted = [...activities]
      ..sort((a, b) => (a.date + a.timeOfDay).compareTo(b.date + b.timeOfDay));

    final zoneSeconds = List<int>.filled(4, 0);
    for (final a in sorted) {
      final d = zones.distribute(a.hrHistogram);
      for (var i = 0; i < 4; i++) {
        zoneSeconds[i] += d[i];
      }
    }
    final zoneTotal = zoneSeconds.fold<int>(0, (x, y) => x + y);
    final hardShare = zoneTotal == 0
        ? 0
        : ((zoneSeconds[2] + zoneSeconds[3]) * 100 / zoneTotal).round();

    final vergleichbar =
        sorted.where((a) => resolve(a) != SessionType.ausflug).toList();

    // Trend = zweite Hälfte gegen erste Hälfte, gerechnet nur über vergleichbare
    // Einheiten. Unter zwei davon gibt es nichts zu vergleichen, dann ist der Trend 0.
    double trend(double Function(Activity) selector) {
      if (vergleichbar.length < 2) return 0;
      final half = math.max(1, vergleichbar.length ~/ 2);
      final first = vergleichbar.take(half).map(selector).toList();
      final second = vergleichbar.skip(half).map(selector).toList();
      if (second.isEmpty) return 0;
      return _mean(second) - _mean(first);
    }

    final withPace = vergleichbar.where((a) => a.paceSecPerKm > 0).toList();
    double paceTrend = 0;
    if (withPace.length >= 2) {
      final h = withPace.length ~/ 2;
      paceTrend =
          _mean(withPace.skip(h).map((a) => a.paceSecPerKm.toDouble()).toList()) -
              _mean(withPace.take(h).map((a) => a.paceSecPerKm.toDouble()).toList());
    }

    final withHr = sorted.where((a) => a.hrAvg > 0).map((a) => a.hrAvg).toList();
    final withCad =
        sorted.where((a) => a.cadenceAvg > 0).map((a) => a.cadenceAvg).toList();
    final paceAll =
        sorted.where((a) => a.paceSecPerKm > 0).map((a) => a.paceSecPerKm).toList();

    Activity? longest;
    for (final a in sorted) {
      if (longest == null || a.distanceKm > longest.distanceKm) longest = a;
    }

    return SportSummary(
      sport: sport,
      count: sorted.length,
      totalKm: sorted.fold<double>(0, (s, a) => s + a.distanceKm),
      totalSec: sorted.fold<int>(0, (s, a) => s + a.durationSec),
      avgHr: _meanIntOrZero(withHr),
      avgCadence: _meanIntOrZero(withCad),
      avgSpeedKmh: _mean(sorted.map((a) => a.speedAvgKmh).toList()),
      avgPaceSecPerKm: _meanIntOrZero(paceAll),
      longest: longest,
      zoneSeconds: zoneSeconds,
      hardSharePct: hardShare,
      speedTrend: trend((a) => a.speedAvgKmh),
      hrTrend: trend((a) => a.hrAvg.toDouble()),
      cadenceTrend: trend((a) => a.cadenceAvg.toDouble()),
      paceTrend: paceTrend,
      loadScore: SessionClassifier.loadScoreFromZones(zoneSeconds),
      excludedFromTrends: sorted.length - vergleichbar.length,
      trendBasis: vergleichbar.length,
    );
  }

  /// Konkrete Hinweise, was als nächstes zu verbessern wäre.
  static List<String> insights(SportSummary s, HrZones zones) {
    final out = <String>[];

    if (s.hardSharePct > 50) {
      out.add('Du warst in ${s.hardSharePct} % deiner Trainingszeit über ${zones.t2} bpm — '
          'für den Grundlagenaufbau mehr lockere Einheiten unter ${zones.t1} bpm einbauen.');
    } else {
      out.add('Guter Mix: nur ${s.hardSharePct} % deiner Trainingszeit lag im intensiven '
          'Bereich über ${zones.t2} bpm.');
    }

    final cad = Analysis.cadenceCheck(s.sport, s.avgCadence);
    if (cad.verdict != Verdict.noData) {
      final unit = Analysis.cadenceUnit(s.sport);
      out.add(cad.verdict == Verdict.good
          ? 'Kadenz im Schnitt bei ${cad.effectiveValue} $unit — das ist ein guter Bereich.'
          : 'Kadenz im Schnitt bei ${cad.effectiveValue} $unit — ${cad.text}.');
    }

    out.add('Belastung gesamt: ${s.loadScore} Punkte '
        '(Minuten je Pulszone, nach Intensität gewichtet).');

    if (s.excludedFromTrends > 0) {
      final n = s.excludedFromTrends;
      out.add('$n Einheit${n > 1 ? 'en' : ''} als Ausflug eingestuft — zählt bei Distanz '
          'und Belastung mit, bleibt aber aus den Trends heraus, damit gemütliche Runden '
          'nicht wie ein Rückschritt aussehen.');
    }

    if (s.trendBasis >= 2) {
      if (s.sport == Sport.running) {
        // Beim Laufen ist weniger besser: negative Pace-Differenz heißt schneller.
        if (s.paceTrend < -5) {
          out.add('Deine Pace verbessert sich '
              '(${Analysis.formatDuration(s.paceTrend.abs().round())} min/km schneller '
              'als am Anfang) — der Aufbau greift.');
        } else if (s.paceTrend > 5) {
          out.add('Deine Pace ist zuletzt etwas langsamer geworden — kann auch an bewusst '
              'ruhigeren Läufen liegen.');
        }
      } else {
        if (s.speedTrend > 0.3) {
          out.add('Dein Ø-Tempo steigt über die letzten Fahrten '
              '(+${s.speedTrend.toStringAsFixed(1)} km/h) — die Grundlage trägt.');
        } else if (s.speedTrend < -0.3) {
          out.add('Dein Ø-Tempo ist zuletzt etwas gesunken '
              '(${s.speedTrend.toStringAsFixed(1)} km/h) — kann auch an bewusst lockereren '
              'Fahrten liegen.');
        }
      }

      // Sinkender Puls bei gleichem oder höherem Tempo ist das eigentliche
      // Fortschrittssignal.
      if (s.hrTrend < -2 && s.speedTrend >= -0.2) {
        out.add('Dein Puls sinkt bei gleichem Tempo '
            '(${s.hrTrend.toStringAsFixed(0)} bpm) — das ist das deutlichste Zeichen für '
            'bessere Ausdauer.');
      }
    } else {
      out.add('Ab der zweiten vergleichbaren Einheit dieser Sportart zeigt dir die App '
          'auch Trends.');
    }

    return out;
  }
}

double _mean(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

int _meanIntOrZero(List<int> values) => values.isEmpty
    ? 0
    : (values.reduce((a, b) => a + b) / values.length).round();
