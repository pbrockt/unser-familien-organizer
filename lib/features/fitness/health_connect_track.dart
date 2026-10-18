import 'dart:math' as math;

import 'health_connect_mapping.dart';

/// Unterordner für die Fahrten, die aus Health Connect gebaut werden.
const String kHcTrackFolderName = 'Trainings';

/// Abstand der Zeilen. Zwei Sekunden reichen für Karte, Verlauf und Standzeit und halten
/// eine Stunde Fahrt bei gut 100 KB.
const int _schrittSec = 2;

/// Ohne neuen Messwert so lange gilt das letzte Tempo noch. Danach heißt Stille: Stand —
/// etwa wenn die Uhr automatisch pausiert und gar nichts mehr schreibt.
const int _gueltigSec = 10;

/// Dateiname der Fahrt, z. B. `2026-10-15_153000_rad_hc.csv`.
///
/// Bewusst so gebaut, dass der vorhandene Leser alles daraus nimmt: Datum und Uhrzeit
/// aus dem Namen, „rad" bzw. „lauf" für die Sportart, und das Ende `_hc.csv` kennzeichnet
/// die Herkunft — eine Datei vom Radcomputer geht ihr vor.
String trainingTrackFileName(HcTraining t) {
  final v = t.from.toLocal();
  String z(int x) => x.toString().padLeft(2, '0');
  return '${dayKey(v)}_${z(v.hour)}${z(v.minute)}${z(v.second)}_'
      '${t.isCycling ? 'rad' : 'lauf'}_hc.csv';
}

/// Baut aus einer Einheit eine CSV im Format des Trackers — damit sie mit Karte,
/// Tempo- und Pulsverlauf, Höhenprofil und Standzeit erscheint wie jede Fahrt aus einer
/// Datei.
///
/// `null`, wenn es kein Tempo gibt: weder Geschwindigkeitswerte noch eine Strecke noch
/// Distanz-Abschnitte. Ein Verlauf, der nur 0 km/h zeigt, wäre schlechter als keiner.
String? trainingTrackCsv({
  required HcTraining training,
  required List<HcSample> samples,
  List<HcRoute> routes = const [],
}) {
  final von = training.from, bis = training.to;
  bool drin(DateTime t) => !t.isBefore(von) && !t.isAfter(bis);

  // Je Art die Werte der Quelle, die die Einheit eingetragen hat — sonst alle.
  List<HcSample> art(HcKind k) {
    final alle = samples.where((s) => s.kind == k && drin(s.from)).toList()
      ..sort((a, b) => a.from.compareTo(b.from));
    final eigene = alle.where((s) => s.source == training.source).toList();
    return eigene.isNotEmpty ? eigene : alle;
  }

  final tempo = art(HcKind.speed);
  final abschnitte = art(HcKind.distance);
  final puls = () {
    final q = dominantSources(samples)[HcKind.heartRate];
    return samples
        .where((s) => s.kind == HcKind.heartRate && drin(s.from) && (q == null || s.source == q))
        .toList()
      ..sort((a, b) => a.from.compareTo(b.from));
  }();
  final strecke = [
    for (final r in routes)
      for (final p in r.points)
        if (drin(p.time)) p,
  ]..sort((a, b) => a.time.compareTo(b.time));

  if (tempo.isEmpty && strecke.length < 2 && abschnitte.isEmpty) return null;

  final zeilen = <String>[
    '"time","TIME_OF_DAY","ALTITUDE","CADENCE","DISTANCE_m","HR","SPEED_mps",'
        '"ASCENT","DESCENT","LATITUDE","LONGITUDE"',
  ];

  var iTempo = 0, iPuls = 0, iStrecke = 0, iAbschnitt = 0;
  var meter = 0.0, anstieg = 0.0, abstieg = 0.0;
  double? hoehenBezug;

  for (var t = von; !t.isAfter(bis); t = t.add(const Duration(seconds: _schrittSec))) {
    while (iTempo + 1 < tempo.length && !tempo[iTempo + 1].from.isAfter(t)) {
      iTempo++;
    }
    while (iPuls + 1 < puls.length && !puls[iPuls + 1].from.isAfter(t)) {
      iPuls++;
    }
    while (iStrecke + 1 < strecke.length && !strecke[iStrecke + 1].time.isAfter(t)) {
      iStrecke++;
    }
    while (iAbschnitt < abschnitte.length && !abschnitte[iAbschnitt].to.isAfter(t)) {
      iAbschnitt++;
    }

    double? frisch(DateTime? wann, double? wert) =>
        wann != null && !wann.isAfter(t) && t.difference(wann).inSeconds <= _gueltigSec
            ? wert
            : null;

    // Tempo: Messwert der Uhr, sonst aus der Strecke, sonst aus Distanz-Abschnitten.
    double geschwindigkeit;
    if (tempo.isNotEmpty) {
      final s = tempo[iTempo];
      geschwindigkeit = frisch(s.from, s.value) ?? 0;
    } else if (strecke.length >= 2) {
      geschwindigkeit = _streckenTempo(strecke, iStrecke, t);
    } else {
      final a = iAbschnitt < abschnitte.length ? abschnitte[iAbschnitt] : null;
      final dauer = a == null ? 0 : a.to.difference(a.from).inSeconds;
      geschwindigkeit = a != null && !a.from.isAfter(t) && dauer > 0 ? a.value / dauer : 0;
    }
    meter += geschwindigkeit * _schrittSec;

    final p = puls.isEmpty ? null : puls[iPuls];
    final bpm = p == null || p.from.isAfter(t) || t.difference(p.from).inSeconds > 30
        ? null
        : p.value.round();

    HcRoutePoint? ort;
    if (strecke.isNotEmpty) {
      final s = strecke[iStrecke];
      if (!s.time.isAfter(t) && t.difference(s.time).inSeconds <= 30) ort = s;
    }
    final hoehe = ort?.altitude;
    if (hoehe != null) {
      // Erst ab einem Meter Änderung zählen — sonst summiert sich GPS-Rauschen zu
      // Höhenmetern, die niemand gefahren ist.
      final bezug = hoehenBezug ??= hoehe;
      if (hoehe - bezug >= 1) {
        anstieg += hoehe - bezug;
        hoehenBezug = hoehe;
      } else if (bezug - hoehe >= 1) {
        abstieg += bezug - hoehe;
        hoehenBezug = hoehe;
      }
    }

    final utc = t.toUtc();
    final lokal = t.toLocal();
    String z(int x) => x.toString().padLeft(2, '0');
    zeilen.add([
      '"${utc.year}-${z(utc.month)}-${z(utc.day)} ${z(utc.hour)}:${z(utc.minute)}:${z(utc.second)}"',
      '"${z(lokal.hour)}:${z(lokal.minute)}:${z(lokal.second)}"',
      '"${hoehe?.toStringAsFixed(1) ?? ''}"',
      '""',
      '"${meter.toStringAsFixed(1)}"',
      '"${bpm ?? ''}"',
      '"${geschwindigkeit.toStringAsFixed(3)}"',
      '"${anstieg.toStringAsFixed(1)}"',
      '"${abstieg.toStringAsFixed(1)}"',
      '"${ort?.lat.toStringAsFixed(6) ?? ''}"',
      '"${ort?.lon.toStringAsFixed(6) ?? ''}"',
    ].join(','));
  }
  return '${zeilen.join('\n')}\n';
}

/// Tempo aus zwei GPS-Punkten um [t]. Liegen sie weiter als [_gueltigSec] auseinander,
/// stand man — oder die Aufzeichnung war unterbrochen.
double _streckenTempo(List<HcRoutePoint> s, int i, DateTime t) {
  if (i + 1 >= s.length || s[i].time.isAfter(t)) return 0;
  final a = s[i], b = s[i + 1];
  final sec = b.time.difference(a.time).inMilliseconds / 1000;
  if (sec <= 0 || sec > _gueltigSec) return 0;
  return _meter(a.lat, a.lon, b.lat, b.lon) / sec;
}

/// Entfernung zweier Punkte in Metern (Haversine).
double _meter(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double g) => g * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h.toDouble()));
}
