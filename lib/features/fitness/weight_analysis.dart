import 'fitness_models.dart';

enum RateVerdict { zuSchnell, gut, langsam, plateau, zunahme, zuWenigDaten }

class WeightPoint {
  const WeightPoint(this.dayOffset, this.kg);
  final int dayOffset;
  final double kg;
}

class WeightTrend {
  const WeightTrend({
    required this.trendKg,
    required this.latestRawKg,
    required this.latestDate,
    required this.ratePerWeek,
    required this.verdict,
    required this.forecastDate,
    required this.goalKg,
    required this.toGoKg,
  });

  /// Aktueller geglätteter Wert — die Zahl, auf die es ankommt.
  final double? trendKg;

  /// Zuletzt gewogener Tageswert.
  final double? latestRawKg;
  final String? latestDate;

  /// Veränderung in kg pro Woche, negativ heißt abnehmend.
  final double? ratePerWeek;
  final RateVerdict verdict;

  /// Erwartetes Datum, an dem das Ziel bei diesem Tempo erreicht wäre.
  final DateTime? forecastDate;
  final double? goalKg;
  final double? toGoKg;
}

/// Alle Rechnungen rund ums Gewicht.
///
/// Der wichtigste Punkt ist die Glättung. Ein Tageswert schwankt durch Wasser, Salz und
/// gefüllte Speicher um bis zu ein Kilo. Wer ihn roh anzeigt, sieht nach einer guten Woche
/// ein Plus und hört auf — deshalb ist überall der gleitende Schnitt die Hauptzahl.
class WeightAnalysis {
  const WeightAnalysis._();

  /// Fenster des gleitenden Schnitts in Tagen.
  static const int windowDays = 7;

  /// Zeitraum, über den die Abnehmrate geschätzt wird.
  static const int _rateWindowDays = 28;

  /// Gleitender Schnitt über ein **Kalenderfenster**, nicht über die letzten N Einträge.
  /// Wer dreimal die Woche wiegt, hätte sonst ein Fenster von zweieinhalb Wochen.
  static List<WeightEntry> movingAverage(List<WeightEntry> entries) {
    final dated = _dated(entries);
    if (dated.isEmpty) return const [];

    return dated.map((cur) {
      final from = cur.key.subtract(const Duration(days: windowDays - 1));
      final window = dated.where((e) =>
          !e.key.isBefore(from) && !e.key.isAfter(cur.key));
      final values = window.map((e) => e.value).toList();
      final avg = values.reduce((a, b) => a + b) / values.length;
      return WeightEntry(_iso(cur.key), avg);
    }).toList();
  }

  /// Wandelt Einträge in Kurvenpunkte mit echtem Tagesabstand um.
  static List<WeightPoint> toPoints(List<WeightEntry> entries) {
    final dated = _dated(entries);
    if (dated.isEmpty) return const [];
    final first = dated.first.key;
    return dated
        .map((e) => WeightPoint(e.key.difference(first).inDays, e.value))
        .toList();
  }

  /// Veränderung in kg pro Woche, geschätzt per Ausgleichsgerade über die Rohwerte der
  /// letzten Wochen. Eine Gerade ist robuster als "heute minus vor 14 Tagen" — dort
  /// bestimmen zwei zufällige Tage das Ergebnis.
  static double? ratePerWeek(List<WeightEntry> entries, DateTime today) {
    final from = today.subtract(const Duration(days: _rateWindowDays));
    final pts = _dated(entries).where((e) => !e.key.isBefore(from)).toList();

    if (pts.length < 4) return null;
    final spanDays = pts.last.key.difference(pts.first.key).inDays;
    // Unter zwei Wochen Abstand ist jede Steigung vor allem Rauschen.
    if (spanDays < 14) return null;

    final xs = pts.map((e) => e.key.millisecondsSinceEpoch / 86400000.0).toList();
    final ys = pts.map((e) => e.value).toList();
    final mx = xs.reduce((a, b) => a + b) / xs.length;
    final my = ys.reduce((a, b) => a + b) / ys.length;

    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < xs.length; i++) {
      num += (xs[i] - mx) * (ys[i] - my);
      den += (xs[i] - mx) * (xs[i] - mx);
    }
    if (den == 0) return null;
    return (num / den) * 7.0;
  }

  static WeightTrend analyse(
    List<WeightEntry> entries,
    double? goalKg,
    DateTime today,
  ) {
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final smoothed = movingAverage(sorted);
    final trend = smoothed.isEmpty ? null : smoothed.last.kg;
    final latest = sorted.isEmpty ? null : sorted.last;
    final rate = ratePerWeek(sorted, today);

    final RateVerdict verdict;
    if (rate == null) {
      verdict = RateVerdict.zuWenigDaten;
    } else if (rate > 0.15) {
      verdict = RateVerdict.zunahme;
    } else if (rate > -0.1) {
      verdict = RateVerdict.plateau;
    } else if (trend != null && rate.abs() > trend * 0.01) {
      // Mehr als ein Prozent des Körpergewichts pro Woche geht überwiegend an die
      // Muskulatur statt ans Fett — und lässt sich selten durchhalten.
      verdict = RateVerdict.zuSchnell;
    } else if (rate.abs() < 0.25) {
      verdict = RateVerdict.langsam;
    } else {
      verdict = RateVerdict.gut;
    }

    DateTime? forecast;
    if (trend != null && goalKg != null && rate != null && rate < -0.02 && goalKg < trend) {
      final weeks = (trend - goalKg) / -rate;
      forecast = today.add(Duration(days: (weeks * 7).round()));
    }

    return WeightTrend(
      trendKg: trend,
      latestRawKg: latest?.kg,
      latestDate: latest?.date,
      ratePerWeek: rate,
      verdict: verdict,
      forecastDate: forecast,
      goalKg: goalKg,
      toGoKg: (trend != null && goalKg != null) ? trend - goalKg : null,
    );
  }

  /// Werte, die deutlich außerhalb der sonst üblichen Wiege-Uhrzeit liegen.
  ///
  /// Das Gewicht schwankt über den Tag um bis zu zwei Kilo. Wer sonst morgens wiegt und
  /// einmal abends, bekommt einen Ausreißer, der wie eine Zunahme aussieht. Die App
  /// rechnet ihn trotzdem mit — sie sagt aber, welcher Wert es ist.
  static Set<String> oddTimeDates(List<WeightEntry> entries) {
    final mitZeit = entries.where((e) => e.hour != null).toList();
    // Unter fünf Werten gibt es keine „übliche" Uhrzeit, an der man messen könnte.
    if (mitZeit.length < 5) return const {};

    final stunden = mitZeit.map((e) => e.hour!).toList()..sort();
    final median = stunden[stunden.length ~/ 2];

    return {
      for (final e in mitZeit)
        if ((e.hour! - median).abs() > 3) e.date,
    };
  }

  static String verdictText(RateVerdict v, double? ratePerWeek) {
    final r = ratePerWeek ?? 0;
    return switch (v) {
      RateVerdict.zuWenigDaten =>
        'Noch zu wenige Werte für einen Trend — ab etwa zwei Wochen regelmäßigem Wiegen '
            'wird er aussagekräftig.',
      RateVerdict.zunahme =>
        'Der Trend zeigt nach oben (${r >= 0 ? '+' : ''}${r.toStringAsFixed(2)} kg/Woche).',
      RateVerdict.plateau =>
        'Das Gewicht steht. Wenn das mehrere Wochen so bleibt, ist kein Defizit da — '
            'unabhängig davon, was an Kalorien gerechnet wurde.',
      RateVerdict.langsam =>
        'Langsam, aber es geht runter (${r.toStringAsFixed(2)} kg/Woche). Das ist gut '
            'durchzuhalten.',
      RateVerdict.gut =>
        'Gutes Tempo (${r.toStringAsFixed(2)} kg/Woche) — im Bereich, der sich halten lässt.',
      RateVerdict.zuSchnell =>
        'Sehr schnell (${r.toStringAsFixed(2)} kg/Woche). Über einem Prozent des '
            'Körpergewichts pro Woche geht viel an die Muskulatur statt ans Fett.',
    };
  }

  static List<MapEntry<DateTime, double>> _dated(List<WeightEntry> entries) {
    final out = <MapEntry<DateTime, double>>[];
    for (final e in entries) {
      final d = DateTime.tryParse(e.date);
      if (d != null) out.add(MapEntry(DateTime(d.year, d.month, d.day), e.kg));
    }
    out.sort((a, b) => a.key.compareTo(b.key));
    return out;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
