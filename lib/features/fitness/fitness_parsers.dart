import 'fitness_analysis.dart';
import 'fitness_models.dart';

const int _maxSeriesPoints = 100;

final RegExp _dateInName = RegExp(r'(\d{4}-\d{2}-\d{2})');
final RegExp _timeInName = RegExp(r'_(\d{2})(\d{2})(\d{2})');

/// Liest eine Trainings-CSV im Format des Trackers (sekundengenaue Telemetrie).
///
/// Ausgewertet werden nicht nur die bekannten Spalten: **jede** Zahlenspalte wird
/// mitgenommen. Was die App nicht kennt, landet als freier Kanal mit Kennzahlen und im
/// Verlauf — so geht nichts verloren, was der Tracker aufzeichnet.
class CsvParser {
  const CsvParser();

  /// Spalten, die vorhanden sein müssen. Kommen Spalten pro Sensor doppelt vor
  /// (z. B. `HR (HUAWEI Band HR-B54)`), gewinnt die erste — also die generische.
  static const _required = [
    'time',
    'ALTITUDE',
    'CADENCE',
    'DISTANCE_m',
    'HR',
    'SPEED_mps',
    'ASCENT',
    'DESCENT',
  ];

  /// Spalten, die eigene Bedeutung haben und deshalb kein freier Kanal werden.
  static const _handled = {..._required};

  Activity? parse(String text, String filename) {
    final lines =
        text.split('\n').where((l) => l.trim().isNotEmpty).toList(growable: false);
    if (lines.length < 2) return null;

    final header = _splitLine(lines.first);
    final idx = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      idx.putIfAbsent(header[i], () => i);
    }
    for (final key in _required) {
      if (!idx.containsKey(key)) return null;
    }

    final iTime = idx['time']!;
    final iAlt = idx['ALTITUDE']!;
    final iCad = idx['CADENCE']!;
    final iDist = idx['DISTANCE_m']!;
    final iHr = idx['HR']!;
    final iSpeed = idx['SPEED_mps']!;
    final iAsc = idx['ASCENT']!;
    final iDesc = idx['DESCENT']!;

    final iLat = _findCoord(idx, isLatitude: true);
    final iLon = _findCoord(idx, isLatitude: false);

    // Freie Kanäle: alles, was übrig bleibt und Zahlen enthält.
    final freeColumns = <String, int>{};
    idx.forEach((name, i) {
      if (_handled.contains(name)) return;
      if (i == iLat || i == iLon) return;
      if (name.trim().isEmpty) return;
      freeColumns[name] = i;
    });

    final rows = lines.skip(1).map(_splitLine).toList(growable: false);

    final histogram = List<int>.filled(hrHistogramSize, 0);
    var hrSum = 0.0, hrCount = 0, hrMax = 0;
    var cadSum = 0.0, cadCount = 0;
    var speedSum = 0.0, speedCount = 0, stoppedCount = 0;
    var movingSum = 0.0, movingCount = 0;
    var speedMax = 0.0, distMax = 0.0;
    var lastAscent = 0.0, lastDescent = 0.0;
    String? firstTime, lastTime;

    // Kennzahlen der freien Kanäle mitziehen, statt die Rohwerte zu behalten.
    final acc = {for (final name in freeColumns.keys) name: _Acc()};

    // Für die bekannten Spalten ebenfalls — nicht zur Anzeige, sondern um die
    // sensorspezifischen Doppelspalten daran zu erkennen. `HR (HUAWEI Band HR-B54)`
    // ist nur dann Rauschen, wenn es dasselbe liefert wie `HR`.
    final bekannt = <String, int>{
      for (final name in _handled)
        if (idx[name] != null && name != 'time') name: idx[name]!,
      // ignore: use_null_aware_elements  (im Map-Literal nicht anwendbar)
      if (iLat != null) 'LATITUDE': iLat,
      // ignore: use_null_aware_elements
      if (iLon != null) 'LONGITUDE': iLon,
    };
    final accBekannt = {for (final name in bekannt.keys) name: _Acc()};

    for (final r in rows) {
      final t = _at(r, iTime);
      if (t != null && t.isNotEmpty) {
        firstTime ??= t;
        lastTime = t;
      }

      final hr = _num(r, iHr);
      if (hr != null && hr > 0) {
        hrSum += hr;
        hrCount++;
        if (hr > hrMax) hrMax = hr.toInt();
        final bin = hr.round();
        if (bin >= 0 && bin < hrHistogramSize) histogram[bin]++;
      }

      // Nur Zyklen unter Last zählen — Rollphasen mit Kadenz 0 würden den Schnitt sonst
      // nach unten ziehen und die Sportart-Erkennung verfälschen.
      final cad = _num(r, iCad);
      if (cad != null && cad > 0) {
        cadSum += cad;
        cadCount++;
      }

      final sp = _num(r, iSpeed);
      if (sp != null) {
        speedSum += sp;
        speedCount++;
        if (sp > speedMax) speedMax = sp;
        // Unter 0,5 m/s (1,8 km/h) steht man — Ampel, Pause, Wartezeit.
        if (sp < 0.5) {
          stoppedCount++;
        } else {
          movingSum += sp;
          movingCount++;
        }
      }

      final d = _num(r, iDist);
      if (d != null && d > distMax) distMax = d;

      final asc = _num(r, iAsc);
      if (asc != null) lastAscent = asc;
      final desc = _num(r, iDesc);
      if (desc != null) lastDescent = desc;

      freeColumns.forEach((name, i) {
        final v = _num(r, i);
        if (v != null) acc[name]!.add(v);
      });
      bekannt.forEach((name, i) {
        final v = _num(r, i);
        if (v != null) accBekannt[name]!.add(v);
      });
    }

    final start = _parseTimestamp(firstTime);
    final end = _parseTimestamp(lastTime);
    final durationSec = (start != null && end != null)
        ? end.difference(start).inSeconds.clamp(0, 1 << 30)
        : 0;

    final cadenceAvg = cadCount > 0 ? (cadSum / cadCount).round() : 0;
    final speedAvgKmh = speedCount > 0 ? speedSum / speedCount * 3.6 : 0.0;

    final series = _buildSeries(
      rows, start, iTime, iHr, iSpeed, iCad, iAlt, iLat, iLon, freeColumns,
    );

    final date = _dateInName.firstMatch(filename)?.group(1) ??
        (firstTime != null && firstTime.length >= 10
            ? firstTime.substring(0, 10)
            : 'unbekannt');
    // Reihenfolge mit Bedacht: die Spalte `time` steht in UTC, `TIME_OF_DAY` in Ortszeit.
    // Ohne diese Bevorzugung zeigte eine Sommerfahrt um 19:01 als 17:01.
    final tm = _timeInName.firstMatch(filename);
    final localTime = idx['TIME_OF_DAY'] == null
        ? null
        : rows
            .map((r) => _at(r, idx['TIME_OF_DAY']!))
            .firstWhere((v) => v != null && v.length >= 5, orElse: () => null);
    final timeOfDay = tm != null
        ? '${tm.group(1)}:${tm.group(2)}'
        : (localTime != null
            ? localTime.substring(0, 5)
            : (firstTime != null && firstTime.length >= 16
                ? firstTime.substring(11, 16)
                : ''));

    final detected = SportDetector.detect(
      filename,
      speedAvgKmh,
      cadenceAvg,
      maxSpeedKmh: speedMax * 3.6,
    );

    final channels = <String, ChannelStat>{};
    acc.forEach((name, a) {
      final stat = a.toStat(name, rows.length);
      if (stat != null) channels[name] = stat;
    });
    final referenz = <String, ChannelStat>{};
    accBekannt.forEach((name, a) {
      final stat = a.toStat(name, rows.length);
      if (stat != null) referenz[name] = stat;
    });
    _dropDuplicates(channels, referenz);

    return Activity(
      id: filename,
      date: date,
      timeOfDay: timeOfDay,
      sportDetected: detected.sport,
      sportConfidence: detected.confidence,
      durationSec: durationSec,
      distanceKm: distMax / 1000.0,
      hrAvg: hrCount > 0 ? (hrSum / hrCount).round() : 0,
      hrMax: hrMax,
      hrHistogram: histogram,
      cadenceAvg: cadenceAvg,
      speedAvgKmh: speedAvgKmh,
      speedMaxKmh: speedMax * 3.6,
      speedMovingAvgKmh: movingCount > 0 ? movingSum / movingCount * 3.6 : 0.0,
      elevGain: lastAscent.round(),
      elevLoss: lastDescent.round(),
      series: series,
      stoppedShare: speedCount > 0 ? stoppedCount / speedCount : 0,
      channels: channels,
    );
  }

  /// Sucht die Spalte mit Breiten- bzw. Längengrad. Tracker benennen sie
  /// unterschiedlich (`LATITUDE`, `lat`, `POSITION_lat`, …), deshalb über Teilstrings.
  int? _findCoord(Map<String, int> idx, {required bool isLatitude}) {
    final treffer = isLatitude
        ? const ['latitude', 'lat_deg', '_lat', 'lat']
        : const ['longitude', 'lon_deg', '_lon', 'lon', 'lng'];
    for (final muster in treffer) {
      for (final entry in idx.entries) {
        final n = entry.key.toLowerCase();
        if (n == muster || n.endsWith(muster) || n.startsWith('$muster ')) {
          return entry.value;
        }
      }
    }
    return null;
  }

  List<TrackPoint> _buildSeries(
    List<List<String>> rows,
    DateTime? start,
    int iTime,
    int iHr,
    int iSpeed,
    int iCad,
    int iAlt,
    int? iLat,
    int? iLon,
    Map<String, int> freeColumns,
  ) {
    if (rows.isEmpty) return const [];
    final step = (rows.length ~/ _maxSeriesPoints).clamp(1, 1 << 30);
    final out = <TrackPoint>[];
    for (var i = 0; i < rows.length; i += step) {
      final r = rows[i];
      final ts = _parseTimestamp(_at(r, iTime));
      final elapsed =
          (ts != null && start != null) ? ts.difference(start).inSeconds : i;

      final extra = <String, double>{};
      freeColumns.forEach((name, ci) {
        final v = _num(r, ci);
        if (v != null) extra[name] = v;
      });

      final lat = iLat == null ? null : _num(r, iLat);
      final lon = iLon == null ? null : _num(r, iLon);

      out.add(TrackPoint(
        elapsedSec: elapsed,
        hr: _num(r, iHr)?.round() ?? 0,
        speedKmh: (_num(r, iSpeed) ?? 0) * 3.6,
        cadence: _num(r, iCad)?.round() ?? 0,
        altitude: _num(r, iAlt) ?? 0,
        // 0/0 ist der Nullpunkt im Atlantik und praktisch immer ein Messfehler.
        lat: (lat == null || lat == 0) ? null : lat,
        lon: (lon == null || lon == 0) ? null : lon,
        extra: extra,
      ));
    }
    return out;
  }

  /// Zerlegt eine Zeile im Format `"a","b","c"`. Fällt auf einfaches Komma-Trennen zurück,
  /// wenn die Zeile nicht durchgehend gequotet ist.
  List<String> _splitLine(String line) {
    final t = line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      return t.substring(1, t.length - 1).split('","');
    }
    return t.split(',');
  }

  String? _at(List<String> row, int i) => i < row.length ? row[i] : null;

  double? _num(List<String> row, int i) {
    final v = _at(row, i)?.trim();
    if (v == null || v.isEmpty) return null;
    return double.tryParse(v);
  }
}

/// Sammelt Kennzahlen einer Spalte im Vorbeigehen.
class _Acc {
  double _min = double.infinity;
  double _max = double.negativeInfinity;
  double _sum = 0;
  int _n = 0;
  double? _vorheriger;
  bool _zaehltHoch = true;

  void add(double v) {
    if (v < _min) _min = v;
    if (v > _max) _max = v;
    _sum += v;
    _n++;
    // Zaehlt die Spalte genau die Zeilen mit? Dann ist sie eine laufende Nummer.
    if (_vorheriger != null && (v - _vorheriger!) != 1.0) _zaehltHoch = false;
    _vorheriger = v;
  }

  /// Gibt Kennzahlen zurück — oder null, wenn die Spalte nichts aussagt.
  ///
  /// Aussortiert werden zwei Sorten stiller Nutzlosigkeit: **laufende Nummern**
  /// (`_id`, `TIME_ACTIVE`, `TIME_TOTAL` zählen schlicht die Zeilen) und **Konstanten**
  /// (`LAP_NR` steht die ganze Fahrt auf 1). Beides als Messwert mit Verlaufsdiagramm
  /// anzuzeigen wäre eine Wand aus Rauschen, in der die echten Werte untergehen.
  ChannelStat? toStat(String name, int zeilen) {
    if (_n == 0) return null;
    if (_min == _max) return null;
    if (_zaehltHoch && _n >= 5 && _min == 1 && _max == _n.toDouble()) return null;
    return ChannelStat(
      name: name,
      min: _min,
      max: _max,
      avg: _sum / _n,
      count: _n,
    );
  }
}

/// Entfernt sensorspezifische Doppelspalten, die denselben Verlauf liefern wie ihre
/// generische Schwester.
///
/// Der Tracker schreibt jede Größe zusätzlich je Quelle mit — `HR (HUAWEI Band HR-B54)`,
/// `LATITUDE (Google Standort (Fused))` und zwei Dutzend weitere. Sie alle als „weitere
/// Messwerte" aufzulisten, ergäbe eine unlesbare Wand aus Wiederholungen. Unterscheiden
/// sich Kennzahlen dagegen, bleibt die Spalte stehen: dann misst der Sensor wirklich
/// etwas anderes.
void _dropDuplicates(
  Map<String, ChannelStat> channels,
  Map<String, ChannelStat> bekannt,
) {
  final basisName = RegExp(r'^(.+?)\s*\(.*\)\s*$');
  final zuLoeschen = <String>[];

  ChannelStat? suche(String name) => bekannt[name] ?? channels[name];

  for (final entry in channels.entries) {
    // a) `X (Sensor)` gegen `X` — der klassische Fall.
    final m = basisName.firstMatch(entry.key);
    if (m != null) {
      final basis = suche(m.group(1)!.trim());
      if (basis != null && _gleich(basis, entry.value)) {
        zuLoeschen.add(entry.key);
        continue;
      }
    }
    // b) Gleiche Zahlen unter anderem Namen, etwa DISTANCE_m_LAP bei einer Runde.
    //    Zwei Spalten mit identischem Min, Max und Schnitt sagen dasselbe aus.
    for (final ref in bekannt.entries) {
      if (_gleich(ref.value, entry.value)) {
        zuLoeschen.add(entry.key);
        break;
      }
    }
  }
  for (final k in zuLoeschen) {
    channels.remove(k);
  }
}

bool _gleich(ChannelStat a, ChannelStat b) {
  bool nah(double x, double y) {
    final spanne = (a.max - a.min).abs();
    final toleranz = spanne < 0.0001 ? 0.0001 : spanne * 0.01;
    return (x - y).abs() <= toleranz;
  }

  return nah(a.min, b.min) && nah(a.max, b.max) && nah(a.avg, b.avg);
}

DateTime? _parseTimestamp(String? raw) {
  var s = raw?.trim();
  if (s == null || s.isEmpty) return null;
  if (s.endsWith('Z')) s = s.substring(0, s.length - 1);
  // DateTime.parse akzeptiert sowohl "2026-08-25 19:01:02" als auch die T-Schreibweise.
  return DateTime.tryParse(s);
}

/// Liest die Tages-Gesundheitsdaten aus dem YAML-Frontmatter einer .md-Datei.
class HealthParser {
  const HealthParser();

  static final _frontmatter = RegExp(r'^---\s*\n(.*?)\n---', dotAll: true);

  HealthDay? parse(String text, String filename) {
    final body =
        _frontmatter.firstMatch(text.replaceAll('\r\n', '\n'))?.group(1);
    if (body == null) return null;

    final fm = <String, String>{};
    for (final line in body.split('\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      var value = line.substring(i + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      fm[line.substring(0, i).trim()] = value;
    }

    final date = (fm['date'] != null && fm['date']!.isNotEmpty)
        ? fm['date']!
        : _dateInName.firstMatch(filename)?.group(1);
    if (date == null) return null;

    double? d(String key) {
      final v = fm[key];
      if (v == null || v.isEmpty) return null;
      return double.tryParse(v);
    }

    int? i(String key) => d(key)?.round();

    return HealthDay(
      date: date,
      steps: i('steps'),
      sleepHours: d('sleep_total_hours'),
      activeCalories: i('active_calories'),
      totalCalories: i('total_calories'),
      hrAvg: i('average_heart_rate'),
      hrMin: i('heart_rate_min'),
      hrMax: i('heart_rate_max'),
      spo2Avg: i('blood_oxygen_avg') ?? i('blood_oxygen'),
      spo2Min: i('blood_oxygen_min'),
      weightKg: d('weight_kg') ?? d('weight') ?? d('gewicht'),
    );
  }
}
