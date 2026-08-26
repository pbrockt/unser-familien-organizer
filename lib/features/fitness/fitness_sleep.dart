import 'fitness_models.dart';

/// Bewertung einer einzelnen Nacht.
class SleepNight {
  const SleepNight({
    required this.date,
    required this.totalHours,
    this.deepHours,
    this.remHours,
    this.coreHours,
    this.awakeHours,
    this.bedtime,
    this.wakeTime,
  });

  final String date;
  final double totalHours;
  final double? deepHours;
  final double? remHours;
  final double? coreHours;
  final double? awakeHours;
  final String? bedtime;
  final String? wakeTime;

  bool get hasPhases => deepHours != null || remHours != null;

  /// Anteil Tiefschlaf an der Schlafzeit.
  double? get deepShare =>
      (deepHours != null && totalHours > 0) ? deepHours! / totalHours : null;

  double? get remShare =>
      (remHours != null && totalHours > 0) ? remHours! / totalHours : null;

  /// Anteil der Zeit im Bett, die tatsächlich Schlaf war.
  ///
  /// Der Tracker zählt die Wachphasen zur Bettzeit; wer viel wach liegt, hat trotz
  /// langer Nacht wenig geschlafen. Genau das verschweigt eine reine Stundenzahl.
  double? get efficiency {
    final wach = awakeHours;
    if (wach == null || totalHours <= 0) return null;
    return ((totalHours - wach) / totalHours).clamp(0.0, 1.0);
  }
}

/// Zusammenfassung mehrerer Nächte.
class SleepSummary {
  const SleepSummary({
    required this.nights,
    required this.avgHours,
    required this.avgDeepShare,
    required this.avgRemShare,
    required this.bedtimeSpreadMinutes,
    required this.typicalBedtime,
  });

  final List<SleepNight> nights;
  final double avgHours;
  final double? avgDeepShare;
  final double? avgRemShare;

  /// Wie stark die Zubettgehzeit schwankt, in Minuten (Standardabweichung).
  ///
  /// Ein gleichmäßiger Rhythmus ist einer der wenigen Schlaf-Hebel, den man selbst in
  /// der Hand hat — und man sieht ihn nur, wenn man die Streuung misst statt den Schnitt.
  final int? bedtimeSpreadMinutes;

  /// Übliche Zubettgehzeit als `HH:mm`.
  final String? typicalBedtime;

  bool get hasData => nights.isNotEmpty;
}

/// Wertet die Schlafdaten der Tagesdateien aus.
class SleepAnalysis {
  const SleepAnalysis._();

  /// Richtwerte: rund 15 % Tiefschlaf und 20 % REM gelten bei Erwachsenen als üblich.
  static const double deepTarget = 0.15;
  static const double remTarget = 0.20;

  static SleepSummary summarize(List<HealthDay> days, {int letzte = 30}) {
    final naechte = <SleepNight>[];
    for (final d in days) {
      final gesamt = d.sleepHours;
      if (gesamt == null || gesamt <= 0) continue;
      naechte.add(SleepNight(
        date: d.date,
        totalHours: gesamt,
        deepHours: d.sleepDeepHours,
        remHours: d.sleepRemHours,
        coreHours: d.sleepCoreHours,
        awakeHours: d.sleepAwakeHours,
        bedtime: d.bedtime,
        wakeTime: d.wakeTime,
      ));
    }
    naechte.sort((a, b) => a.date.compareTo(b.date));
    final jung =
        naechte.length > letzte ? naechte.sublist(naechte.length - letzte) : naechte;

    if (jung.isEmpty) {
      return const SleepSummary(
        nights: [],
        avgHours: 0,
        avgDeepShare: null,
        avgRemShare: null,
        bedtimeSpreadMinutes: null,
        typicalBedtime: null,
      );
    }

    double? schnittAnteil(Iterable<double?> werte) {
      final gefiltert = werte.whereType<double>().toList();
      if (gefiltert.isEmpty) return null;
      return gefiltert.reduce((a, b) => a + b) / gefiltert.length;
    }

    final rhythmus = _bedtimeRhythm(jung);

    return SleepSummary(
      nights: jung,
      avgHours: jung.map((n) => n.totalHours).reduce((a, b) => a + b) / jung.length,
      avgDeepShare: schnittAnteil(jung.map((n) => n.deepShare)),
      avgRemShare: schnittAnteil(jung.map((n) => n.remShare)),
      bedtimeSpreadMinutes: rhythmus.$1,
      typicalBedtime: rhythmus.$2,
    );
  }

  /// Streuung und Mittel der Zubettgehzeit.
  ///
  /// Gerechnet wird um Mitternacht herum: 23:50 und 00:10 liegen zwanzig Minuten
  /// auseinander, nicht dreiundzwanzig Stunden. Zeiten nach 12 Uhr mittags werden
  /// deshalb als „vor Mitternacht" ins Negative gelegt.
  static (int?, String?) _bedtimeRhythm(List<SleepNight> naechte) {
    final minuten = <double>[];
    for (final n in naechte) {
      final m = _toMinutes(n.bedtime);
      if (m == null) continue;
      minuten.add(m >= 12 * 60 ? m - 24 * 60 : m);
    }
    if (minuten.length < 3) return (null, null);

    final schnitt = minuten.reduce((a, b) => a + b) / minuten.length;
    final varianz = minuten
            .map((m) => (m - schnitt) * (m - schnitt))
            .reduce((a, b) => a + b) /
        minuten.length;
    final streuung = _sqrt(varianz).round();

    var mittel = schnitt.round() % (24 * 60);
    if (mittel < 0) mittel += 24 * 60;
    final h = (mittel ~/ 60).toString().padLeft(2, '0');
    final m = (mittel % 60).toString().padLeft(2, '0');
    return (streuung, '$h:$m');
  }

  static double? _toMinutes(String? hhmm) {
    if (hhmm == null || hhmm.length < 4) return null;
    final teile = hhmm.split(':');
    if (teile.length != 2) return null;
    final h = int.tryParse(teile[0]);
    final m = int.tryParse(teile[1]);
    if (h == null || m == null) return null;
    return (h * 60 + m).toDouble();
  }

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    var x = v;
    for (var i = 0; i < 20; i++) {
      x = (x + v / x) / 2;
    }
    return x;
  }

  /// Hinweise zum Schlaf — bewusst wenige und ohne Ursachenbehauptungen.
  static List<String> insights(SleepSummary s) {
    if (!s.hasData) return const [];
    final out = <String>[];

    out.add('Ø ${s.avgHours.toStringAsFixed(1)} Stunden über '
        '${s.nights.length} ${s.nights.length == 1 ? 'Nacht' : 'Nächte'}.');

    final tief = s.avgDeepShare;
    if (tief != null) {
      final prozent = (tief * 100).round();
      if (tief < deepTarget * 0.6) {
        out.add('Nur $prozent % Tiefschlaf — üblich sind um die '
            '${(deepTarget * 100).round()} %. Lange im Bett heißt nicht automatisch '
            'gut erholt.');
      } else if (tief >= deepTarget) {
        out.add('$prozent % Tiefschlaf — solide.');
      } else {
        out.add('$prozent % Tiefschlaf, etwas unter dem üblichen Bereich von '
            '${(deepTarget * 100).round()} %.');
      }
    }

    final streuung = s.bedtimeSpreadMinutes;
    if (streuung != null && s.typicalBedtime != null) {
      if (streuung > 90) {
        out.add('Deine Zubettgehzeit schwankt um ±$streuung Minuten um '
            '${s.typicalBedtime} herum. Ein gleichmäßigerer Rhythmus ist der Hebel mit '
            'dem besten Verhältnis von Aufwand zu Wirkung.');
      } else if (streuung <= 45) {
        out.add('Zubettgehzeit sehr gleichmäßig (±$streuung Minuten um '
            '${s.typicalBedtime}) — genau das trägt die Erholung.');
      } else {
        out.add('Zubettgehzeit um ${s.typicalBedtime} herum, ±$streuung Minuten.');
      }
    }

    final wach = s.nights
        .map((n) => n.awakeHours)
        .whereType<double>()
        .toList();
    if (wach.isNotEmpty) {
      final schnitt = wach.reduce((a, b) => a + b) / wach.length;
      if (schnitt > 1.0) {
        out.add('Im Schnitt ${schnitt.toStringAsFixed(1)} Stunden je Nacht wach im '
            'Bett — die zählen zur Bettzeit, aber nicht zur Erholung.');
      }
    }

    return out;
  }
}
