import 'dart:math' as math;
import 'dart:typed_data';

import 'fitness_models.dart';

/// Liest FIT-Dateien — das Format, in dem Trainings-Apps und Radcomputer ihre Einheiten
/// ausgeben (MyWhoosh, Garmin, Wahoo, Zwift).
///
/// FIT ist binär und selbstbeschreibend: Vor jedem Datensatz steht eine Definition, die
/// sagt, welche Felder in welcher Größe folgen. Deshalb braucht dieser Leser keine
/// vollständige Feldtabelle — unbekannte Felder werden anhand ihrer Größe übersprungen,
/// statt die Datei abzulehnen. Genau das macht das Format über Herstellergrenzen hinweg
/// lesbar, und genau darauf ist dieser Leser ausgelegt.
///
/// Bewusst kein Paket: Es geht um einen Dateikopf, eine Definitionstabelle und
/// Ganzzahlen in zwei Byte-Reihenfolgen. Eine Abhängigkeit dafür wäre mehr Risiko als
/// Ersparnis, und die Dateien kommen aus der Nextcloud — ungeprüfte Eingabe, bei der ich
/// wissen will, was der Leser tut.
class FitParser {
  const FitParser();

  /// Höchstens so viele Punkte im gespeicherten Verlauf — wie beim CSV-Leser.
  static const int _maxSeriesPoints = 100;

  /// Darunter steht man. Dieselbe Schwelle wie im CSV-Leser, damit „Bewegungszeit" in
  /// der ganzen App dasselbe heißt.
  static const double _stoppedBelowMps = 0.5;

  /// Größere Sprünge sind Aufzeichnungslücken und keine Fahrzeit.
  static const int _maxGapSec = 60;

  /// FIT rechnet Zeitstempel ab dem 31.12.1989, nicht ab 1970.
  static final DateTime _epoch = DateTime.utc(1989, 12, 31);

  /// Gibt `null` zurück, wenn die Datei keine lesbare Einheit enthält — dieselbe
  /// Vereinbarung wie beim CSV-Leser, damit der Abgleich beides gleich behandeln kann.
  Activity? parse(Uint8List bytes, String filename) {
    final _FitFile datei;
    try {
      datei = _read(bytes);
    } catch (_) {
      // Abgebrochene Übertragung, fremdes Format, beschädigte Datei: alles kein Grund,
      // den ganzen Abgleich scheitern zu lassen.
      return null;
    }

    final punkte = datei.records;
    if (punkte.length < 2) return null;

    final sitzung = datei.session;
    final sport = _sportOf(sitzung?[_fSport] as int?);
    final indoor = _indoorSubSports.contains(sitzung?[_fSubSport] as int?);

    // Zeit: die Datei nennt Gesamt- und Uhrzeit selbst. Wo sie das nicht tut, bleibt der
    // Abstand zwischen erstem und letztem Messpunkt.
    final start = punkte.first.time;
    final ende = punkte.last.time;
    final gesamtSec = _seconds(sitzung?[_fElapsed]) ??
        (start != null && ende != null ? ende.difference(start).inSeconds : 0);

    final histogram = List<int>.filled(hrHistogramSize, 0);
    var hrSum = 0.0, hrCount = 0, hrMax = 0;
    var cadSum = 0.0, cadCount = 0;
    var speedSum = 0.0, speedCount = 0, speedMax = 0.0;
    var movingSum = 0.0, movingCount = 0;
    var bewegtSec = 0, gemesseneSec = 0;
    var wattSum = 0.0, wattCount = 0, wattMax = 0;
    // Für die Prüfung, ob die Watt überhaupt gemessen sind: das Verhältnis zur
    // Trittfrequenz an jedem Punkt, und wie viele verschiedene Wattwerte vorkommen.
    final wattJeKadenz = <double>[];
    final wattWerte = <int>{};
    var hoeheMin = double.infinity, hoeheMax = -double.infinity;
    var anstieg = 0.0, abstieg = 0.0;
    double? vorigeHoehe;
    DateTime? vorigeZeit;

    for (final p in punkte) {
      final abstand = (p.time != null && vorigeZeit != null)
          ? p.time!.difference(vorigeZeit).inSeconds
          : 0;
      final gewicht = (abstand > 0 && abstand <= _maxGapSec) ? abstand : 1;

      final hr = p.hr;
      if (hr != null && hr > 0) {
        // Nach Zeitabstand gewichtet, nicht je Zeile: Ein Gerät, das nur alle fünf
        // Sekunden schreibt, hätte sonst ein fünffach zu dünnes Histogramm — und damit
        // einen Belastungswert, der nicht zu dem einer Sekunden-Aufzeichnung passt.
        hrSum += hr * gewicht;
        hrCount += gewicht;
        if (hr > hrMax) hrMax = hr;
        if (hr >= 0 && hr < hrHistogramSize) histogram[hr] += gewicht;
      }

      final cad = p.cadence;
      if (cad != null && cad > 0) {
        cadSum += cad;
        cadCount++;
      }

      final sp = p.speedMps;
      if (sp != null) {
        speedSum += sp;
        speedCount++;
        if (sp > speedMax) speedMax = sp;
        if (sp >= _stoppedBelowMps) {
          movingSum += sp;
          movingCount++;
        }
        if (abstand > 0 && abstand <= _maxGapSec) {
          gemesseneSec += abstand;
          if (sp >= _stoppedBelowMps) bewegtSec += abstand;
        }
      }

      final w = p.power;
      if (w != null) {
        wattSum += w;
        wattCount++;
        if (w > wattMax) wattMax = w;
        wattWerte.add(w);
        if (cad != null && cad > 10 && w > 0) wattJeKadenz.add(w / cad);
      }

      final h = p.altitude;
      if (h != null) {
        hoeheMin = math.min(hoeheMin, h);
        hoeheMax = math.max(hoeheMax, h);
        if (vorigeHoehe != null) {
          final d = h - vorigeHoehe;
          // Ein halber Meter ist Rauschen des Höhensensors. Ohne Schwelle summieren sich
          // Tausende Zuckungen zu Höhenmetern, die niemand gefahren ist.
          if (d > 0.5) {
            anstieg += d;
          } else if (d < -0.5) {
            abstieg -= d;
          }
        }
        vorigeHoehe = h;
      }

      if (p.time != null) vorigeZeit = p.time;
    }

    // Die Datei kennt ihre Fahrzeit oft selbst (`total_timer_time`, ohne Auto-Pause).
    // Die kleinere der beiden Zahlen gewinnt: Der Zeitgeber kennt die Pausen, die das
    // Gerät erkannt hat, die Geschwindigkeitsschwelle die übrigen — etwa eine Ampel, an
    // der niemand die Aufzeichnung anhält.
    final timerSec = _seconds(sitzung?[_fTimer]) ?? 0;
    final movingSec = bewegtSec > 0
        ? (timerSec > 0 ? math.min(bewegtSec, timerSec) : bewegtSec)
        : timerSec;

    final distanzKm = _scaled(sitzung?[_fTotalDistance], 100) != null
        ? _scaled(sitzung?[_fTotalDistance], 100)! / 1000.0
        : (punkte.last.distanceM ?? 0) / 1000.0;

    final speedAvgKmh = _scaled(sitzung?[_fAvgSpeed], 1000) != null
        ? _scaled(sitzung?[_fAvgSpeed], 1000)! * 3.6
        : (speedCount > 0 ? speedSum / speedCount * 3.6 : 0.0);
    final speedMaxKmh = math.max(
      speedMax * 3.6,
      (_scaled(sitzung?[_fMaxSpeed], 1000) ?? 0) * 3.6,
    );

    final gerechnet = powerLooksDerived(wattJeKadenz, wattWerte.length);

    final zeit = start?.toLocal();
    final kanaele = <String, ChannelStat>{};
    if (wattCount > 0) {
      // Als Kanal *und* als eigene Kennzahl: Die Kennzahl steht vorn bei Distanz und
      // Puls, der Kanal bringt den Verlauf mit, ohne dass es dafür neue Anzeige braucht.
      kanaele['POWER'] = ChannelStat(
        name: 'POWER',
        min: 0,
        max: wattMax.toDouble(),
        avg: wattSum / wattCount,
        count: wattCount,
      );
    }

    return Activity(
      id: filename,
      date: zeit == null
          ? 'unbekannt'
          : '${zeit.year.toString().padLeft(4, '0')}-'
              '${zeit.month.toString().padLeft(2, '0')}-'
              '${zeit.day.toString().padLeft(2, '0')}',
      // FIT speichert UTC. Ohne Umrechnung stünde eine Nachmittagsfahrt zwei Stunden
      // früher da — und eine Fahrt nach 22 Uhr am falschen Tag.
      timeOfDay: zeit == null
          ? ''
          : '${zeit.hour.toString().padLeft(2, '0')}:'
              '${zeit.minute.toString().padLeft(2, '0')}',
      // Die Datei nennt die Sportart. Raten wäre hier schlicht schlechter.
      sportDetected: sport,
      sportConfidence: sport == Sport.unknown ? 0 : 1,
      sportDeclared: sport == Sport.unknown ? null : sport,
      durationSec: gesamtSec,
      movingSec: movingSec,
      distanceKm: distanzKm,
      hrAvg: (sitzung?[_fAvgHr] as int?) ??
          (hrCount > 0 ? (hrSum / hrCount).round() : 0),
      hrMax: math.max(hrMax, (sitzung?[_fMaxHr] as int?) ?? 0),
      hrHistogram: histogram,
      cadenceAvg: (sitzung?[_fAvgCadence] as int?) ??
          (cadCount > 0 ? (cadSum / cadCount).round() : 0),
      speedAvgKmh: speedAvgKmh,
      speedMaxKmh: speedMaxKmh,
      speedMovingAvgKmh: movingCount > 0 ? movingSum / movingCount * 3.6 : 0.0,
      elevGain: ((sitzung?[_fTotalAscent] as int?) ?? anstieg.round()),
      elevLoss: ((sitzung?[_fTotalDescent] as int?) ?? abstieg.round()),
      series: _series(punkte, start, indoor),
      stoppedShare: gesamtSec > 0 && gemesseneSec > 0
          ? ((gesamtSec - movingSec) / gesamtSec).clamp(0.0, 1.0)
          : 0.0,
      channels: kanaele,
      powerAvg: (sitzung?[_fAvgPower] as int?) ??
          (wattCount > 0 ? (wattSum / wattCount).round() : 0),
      powerMax: math.max(wattMax, (sitzung?[_fMaxPower] as int?) ?? 0),
      powerDerived: gerechnet,
      indoor: indoor,
      laps: datei.laps.length > 1 ? _laps(datei.laps) : const [],
    );
  }

  /// Prüft, ob die Leistung in Wirklichkeit die Trittfrequenz ist.
  ///
  /// Öffentlich, weil sich die Entscheidung nur so mit gestreuten Werten prüfen lässt:
  /// Eine echte Messung nachzubauen hieße sonst, eine FIT-Datei zu fälschen.
  ///
  /// Zwei Merkmale müssen zusammenkommen, damit aus einem Verdacht eine Aussage wird:
  ///
  /// 1. Das Verhältnis Watt je Umdrehung bleibt über die ganze Einheit gleich. Ein
  ///    Mensch tritt nicht mit konstantem Drehmoment — schon gar nicht, während sich die
  ///    Leistung verdoppelt.
  /// 2. Es kommen viel zu wenige verschiedene Wattwerte vor. Ein echter Leistungsmesser
  ///    schwankt im Sekundentakt und liefert Hunderte verschiedener Zahlen; eine
  ///    gerechnete Leistung nur so viele, wie es ganzzahlige Trittfrequenzen gibt.
  ///
  /// Nur eines von beidem reicht nicht: Eine gleichmäßig getretene Einheit erfüllt
  /// Merkmal 1 beinahe, und ein stark geglätteter Messwert Merkmal 2.
  static bool powerLooksDerived(List<double> verhaeltnisse, int verschiedeneWatt) {
    // Unter einer Minute Messpunkte ist jede Aussage darüber Zufall.
    if (verhaeltnisse.length < 60) return false;

    final sortiert = [...verhaeltnisse]..sort();
    final median = sortiert[sortiert.length ~/ 2];
    if (median <= 0) return false;

    final nahDran =
        verhaeltnisse.where((v) => (v - median).abs() / median < 0.10).length;
    final konstant = nahDran / verhaeltnisse.length >= 0.90;

    // Ein echter Leistungsmesser füllt den Wertebereich; vier Messpunkte je
    // vorkommendem Wattwert sind dafür schon sehr grob.
    final grobGerastert = verschiedeneWatt * 4 < verhaeltnisse.length;

    return konstant && grobGerastert;
  }

  /// Rechnet den Verlauf auf höchstens [_maxSeriesPoints] Punkte herunter.
  ///
  /// Bei einer Einheit drinnen bleiben die Koordinaten weg: Sie zeigen auf die Stelle der
  /// Erde, die die virtuelle Welt nachbildet. Eine Karte daraus wäre eine Behauptung.
  List<TrackPoint> _series(List<_Record> punkte, DateTime? start, bool indoor) {
    final schritt = (punkte.length / _maxSeriesPoints).ceil().clamp(1, 1 << 20);
    final out = <TrackPoint>[];
    for (var i = 0; i < punkte.length; i += schritt) {
      final p = punkte[i];
      out.add(TrackPoint(
        elapsedSec: (p.time != null && start != null)
            ? p.time!.difference(start).inSeconds
            : i,
        hr: p.hr ?? 0,
        speedKmh: (p.speedMps ?? 0) * 3.6,
        cadence: p.cadence ?? 0,
        altitude: p.altitude ?? 0,
        lat: indoor ? null : p.lat,
        lon: indoor ? null : p.lon,
        extra: {if (p.power != null) 'POWER': p.power!.toDouble()},
      ));
    }
    return out;
  }

  List<ActivityLap> _laps(List<Map<int, Object?>> roh) {
    final out = <ActivityLap>[];
    for (var i = 0; i < roh.length; i++) {
      final l = roh[i];
      final sec = _seconds(l[_fLapTimer]) ?? _seconds(l[_fLapElapsed]) ?? 0;
      // Runden ohne Dauer sind Randnotizen des Geräts, keine gefahrenen Abschnitte.
      if (sec <= 0) continue;
      out.add(ActivityLap(
        number: out.length + 1,
        durationSec: sec,
        distanceKm: (_scaled(l[_fLapDistance], 100) ?? 0) / 1000.0,
        avgSpeedKmh: (_scaled(l[_fLapAvgSpeed], 1000) ?? 0) * 3.6,
        avgHr: (l[_fLapAvgHr] as int?) ?? 0,
        maxHr: (l[_fLapMaxHr] as int?) ?? 0,
        avgCadence: (l[_fLapAvgCadence] as int?) ?? 0,
        avgPower: (l[_fLapAvgPower] as int?) ?? 0,
        maxPower: (l[_fLapMaxPower] as int?) ?? 0,
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------- Binärteil

  _FitFile _read(Uint8List bytes) {
    if (bytes.length < 14) throw const FormatException('zu kurz');
    if (String.fromCharCodes(bytes.sublist(8, 12)) != '.FIT') {
      throw const FormatException('keine FIT-Datei');
    }
    final kopf = bytes[0];
    final daten = ByteData.sublistView(bytes);
    final laenge = daten.getUint32(4, Endian.little);
    // Der Datenteil endet vor der Prüfsumme. Abgeschnittene Dateien nennen oft eine zu
    // große Länge — deshalb zusätzlich an der echten Dateigröße begrenzen.
    final ende = math.min(kopf + laenge, bytes.length);

    final datei = _FitFile();
    final defs = <int, _Definition>{};
    var pos = kopf;
    DateTime? letzteZeit;

    while (pos < ende) {
      final header = bytes[pos];
      pos++;

      if (header & 0x80 != 0) {
        // Kopf mit komprimiertem Zeitstempel: fünf Bits Versatz auf die letzte Zeit.
        // Garmin nutzt das, um Platz zu sparen; ohne diesen Zweig bräche der Leser
        // mitten in einer sonst gesunden Datei ab.
        final local = (header >> 5) & 0x03;
        final def = defs[local];
        if (def == null) throw const FormatException('unbekannter Satztyp');
        final versatz = header & 0x1F;
        final werte = _readFields(bytes, daten, pos, def);
        pos += def.size;
        if (letzteZeit != null) {
          final basis = letzteZeit.millisecondsSinceEpoch ~/ 1000;
          final voll = basis + ((versatz - basis) & 0x1F);
          letzteZeit = DateTime.fromMillisecondsSinceEpoch(voll * 1000, isUtc: true);
          werte[_fTimestamp] = (voll - _epoch.millisecondsSinceEpoch ~/ 1000);
        }
        _collect(datei, def.global, werte);
        continue;
      }

      final local = header & 0x0F;
      if (header & 0x40 != 0) {
        // Definitionssatz.
        final arch = bytes[pos + 1];
        final e = arch == 0 ? Endian.little : Endian.big;
        final global = daten.getUint16(pos + 2, e);
        final anzahl = bytes[pos + 4];
        pos += 5;
        final felder = <_Field>[];
        for (var i = 0; i < anzahl; i++) {
          felder.add(_Field(bytes[pos], bytes[pos + 1], bytes[pos + 2] & 0x1F));
          pos += 3;
        }
        var devSize = 0;
        if (header & 0x20 != 0) {
          final n = bytes[pos];
          pos++;
          for (var i = 0; i < n; i++) {
            devSize += bytes[pos + 1];
            pos += 3;
          }
        }
        defs[local] = _Definition(global, e, felder, devSize);
      } else {
        final def = defs[local];
        if (def == null) throw const FormatException('Satz ohne Definition');
        final werte = _readFields(bytes, daten, pos, def);
        pos += def.size;
        final ts = werte[_fTimestamp];
        if (ts is int) {
          letzteZeit =
              _epoch.add(Duration(seconds: ts));
        }
        _collect(datei, def.global, werte);
      }
    }
    return datei;
  }

  /// Liest die Felder eines Datensatzes. Entwicklerfelder werden übersprungen: Ihre
  /// Bedeutung steht in einer eigenen Beschreibung, und keines davon trägt Messwerte,
  /// die hier gebraucht werden.
  Map<int, Object?> _readFields(
    Uint8List bytes,
    ByteData daten,
    int pos,
    _Definition def,
  ) {
    final werte = <int, Object?>{};
    var p = pos;
    for (final f in def.felder) {
      final info = _baseTypes[f.base];
      if (info == null || p + f.size > bytes.length) {
        p += f.size;
        continue;
      }
      werte[f.num] = _value(daten, p, f, info, def.endian);
      p += f.size;
    }
    return werte;
  }

  Object? _value(
    ByteData daten,
    int pos,
    _Field f,
    _BaseType info,
    Endian e,
  ) {
    // Felder können Listen sein. Gebraucht wird hier immer nur der erste Wert — die
    // Listenfelder des Formats sind Zonen-Tabellen und Gerätekennungen.
    if (f.size < info.size) return null;
    final num? roh = switch (info.size) {
      1 => info.signed ? daten.getInt8(pos) : daten.getUint8(pos),
      2 => info.signed ? daten.getInt16(pos, e) : daten.getUint16(pos, e),
      4 => info.float
          ? daten.getFloat32(pos, e)
          : (info.signed ? daten.getInt32(pos, e) : daten.getUint32(pos, e)),
      8 => info.float
          ? daten.getFloat64(pos, e)
          : (info.signed ? daten.getInt64(pos, e) : daten.getUint64(pos, e)),
      _ => null,
    };
    if (roh == null) return null;
    if (info.invalid != null && roh == info.invalid) return null;
    return roh is double ? roh : roh.toInt();
  }

  void _collect(_FitFile datei, int global, Map<int, Object?> werte) {
    switch (global) {
      case _mSession:
        // Die letzte Sitzung gewinnt: Mehrsport-Dateien schreiben je Teil eine, und die
        // abschließende trägt die Summe.
        datei.session = werte;
      case _mLap:
        datei.laps.add(werte);
      case _mRecord:
        final ts = werte[_fTimestamp];
        datei.records.add(_Record(
          time: ts is int ? _epoch.add(Duration(seconds: ts)) : null,
          hr: werte[_fHr] as int?,
          cadence: werte[_fCadence] as int?,
          power: werte[_fPower] as int?,
          // Die „enhanced"-Felder sind dieselbe Größe mit mehr Wertebereich. Wo beide
          // stehen, ist das gewöhnliche Feld bei schnellen Fahrten übergelaufen.
          speedMps: _scaled(werte[_fEnhancedSpeed] ?? werte[_fSpeed], 1000),
          distanceM: _scaled(werte[_fDistance], 100),
          altitude: _altitude(werte[_fEnhancedAltitude] ?? werte[_fAltitude]),
          lat: _semicircles(werte[_fLat]),
          lon: _semicircles(werte[_fLon]),
        ));
    }
  }

  static Sport _sportOf(int? fit) => switch (fit) {
        1 => Sport.running,
        2 => Sport.cycling,
        // 11 = Gehen, 17 = Wandern: beides wird hier wie Laufen bewertet, weil es in
        // denselben Kennzahlen aufgeht. Alles andere bleibt offen statt falsch.
        11 || 17 => Sport.running,
        _ => Sport.unknown,
      };

  /// Unterarten, die drinnen stattfinden: Spinning, Rolle, virtuelle Welt, Laufband.
  static const Set<int> _indoorSubSports = {1, 5, 6, 14, 15, 16, 25, 26, 27, 45, 58};

  static int? _seconds(Object? roh) => _scaled(roh, 1000)?.round();

  static double? _scaled(Object? roh, num teiler) =>
      roh is num ? roh / teiler : null;

  /// Höhe steckt mit Maßstab 5 und Versatz 500 im Feld — so passen negative Höhen in
  /// eine vorzeichenlose Zahl.
  static double? _altitude(Object? roh) =>
      roh is num ? roh / 5.0 - 500.0 : null;

  /// Positionen stehen in Semicircles: 2^31 entspricht 180 Grad.
  static double? _semicircles(Object? roh) =>
      roh is num ? roh * (180.0 / 2147483648.0) : null;
}

// ------------------------------------------------------------- Nachrichtennummern

const int _mSession = 18;
const int _mLap = 19;
const int _mRecord = 20;

const int _fTimestamp = 253;

// record
const int _fLat = 0;
const int _fLon = 1;
const int _fAltitude = 2;
const int _fHr = 3;
const int _fCadence = 4;
const int _fDistance = 5;
const int _fSpeed = 6;
const int _fPower = 7;
const int _fEnhancedSpeed = 73;
const int _fEnhancedAltitude = 78;

// session
const int _fSport = 5;
const int _fSubSport = 6;
const int _fElapsed = 7;
const int _fTimer = 8;
const int _fTotalDistance = 9;
const int _fAvgSpeed = 14;
const int _fMaxSpeed = 15;
const int _fAvgHr = 16;
const int _fMaxHr = 17;
const int _fAvgCadence = 18;
const int _fAvgPower = 20;
const int _fMaxPower = 21;
const int _fTotalAscent = 22;
const int _fTotalDescent = 23;

// lap — eigene Nummerierung, gegen session um eins verschoben. Genau daran liest man
// sonst Unsinn: Feld 17 ist in der Sitzung der Maximalpuls, in der Runde die Kadenz.
const int _fLapElapsed = 7;
const int _fLapTimer = 8;
const int _fLapDistance = 9;
const int _fLapAvgSpeed = 13;
const int _fLapAvgHr = 15;
const int _fLapMaxHr = 16;
const int _fLapAvgCadence = 17;
const int _fLapAvgPower = 19;
const int _fLapMaxPower = 20;

class _FitFile {
  Map<int, Object?>? session;
  final List<Map<int, Object?>> laps = [];
  final List<_Record> records = [];
}

class _Record {
  const _Record({
    this.time,
    this.hr,
    this.cadence,
    this.power,
    this.speedMps,
    this.distanceM,
    this.altitude,
    this.lat,
    this.lon,
  });

  final DateTime? time;
  final int? hr;
  final int? cadence;
  final int? power;
  final double? speedMps;
  final double? distanceM;
  final double? altitude;
  final double? lat;
  final double? lon;
}

class _Definition {
  _Definition(this.global, this.endian, this.felder, this.devSize);

  final int global;
  final Endian endian;
  final List<_Field> felder;
  final int devSize;

  int get size =>
      felder.fold<int>(0, (s, f) => s + f.size) + devSize;
}

class _Field {
  const _Field(this.num, this.size, this.base);
  final int num;
  final int size;
  final int base;
}

class _BaseType {
  const _BaseType(this.size, {this.signed = false, this.float = false, this.invalid});
  final int size;
  final bool signed;
  final bool float;
  final num? invalid;
}

/// Die Basistypen des Formats mit ihrem jeweiligen „ungültig"-Wert. Der ist nicht Zierde:
/// Ein nicht gemessener Puls steht als 0xFF in der Datei, und ungeprüft wären das 255 bpm.
const Map<int, _BaseType> _baseTypes = {
  0: _BaseType(1, invalid: 0xFF), // enum
  1: _BaseType(1, signed: true, invalid: 0x7F), // sint8
  2: _BaseType(1, invalid: 0xFF), // uint8
  3: _BaseType(2, signed: true, invalid: 0x7FFF), // sint16
  4: _BaseType(2, invalid: 0xFFFF), // uint16
  5: _BaseType(4, signed: true, invalid: 0x7FFFFFFF), // sint32
  6: _BaseType(4, invalid: 0xFFFFFFFF), // uint32
  7: _BaseType(1), // string — hier nicht gebraucht
  8: _BaseType(4, float: true), // float32
  9: _BaseType(8, float: true), // float64
  10: _BaseType(1, invalid: 0), // uint8z
  11: _BaseType(2, invalid: 0), // uint16z
  12: _BaseType(4, invalid: 0), // uint32z
  13: _BaseType(1, invalid: 0xFF), // byte
  14: _BaseType(8, signed: true), // sint64
  15: _BaseType(8), // uint64
  16: _BaseType(8, invalid: 0), // uint64z
};
