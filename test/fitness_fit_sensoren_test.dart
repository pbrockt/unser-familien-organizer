import 'dart:typed_data';

import 'package:family_planner/features/fitness/fitness_fit_parser.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Radcomputer, die Puls und Geschwindigkeit als getrennte Messpunkte in derselben
/// Sekunde schreiben. Nachgebaut nach einer echten E-Bike-Fahrt vom 24.09.2026, die
/// über eine Stunde gefahren war und als halbe Stunde mit 65 % Standzeit erschien.
///
/// Hier bewusst eine gebaute Datei statt der echten: Die echte trägt die Strecke vor
/// der Haustür. Nachgebaut ist genau das Muster, an dem der Leser scheiterte.
void main() {
  const parser = FitParser();

  // 600 s Fahrt mit 5 m/s, dann 300 s Lücke, dann 300 s Fahrt. Jede Sekunde erst ein
  // Pulspunkt, dann ein Geschwindigkeitspunkt mit demselben Zeitstempel.
  final bytes = _fit(
    sport: 21,
    punkte: [
      for (var t = 0; t < 600; t++) ...[_Punkt(t, hr: 140), _Punkt(t, speed: 5.0)],
      for (var t = 900; t < 1200; t++) ...[_Punkt(t, hr: 150), _Punkt(t, speed: 5.0)],
    ],
    elapsedSec: 1199,
    timerSec: 898,
  );

  late final Activity a;
  setUpAll(() => a = parser.parse(bytes, 'ebike.fit')!);

  test('zählt die Fahrzeit, auch wenn der Puls dazwischen schreibt', () {
    // 599 + 299 Sekunden zwischen den Geschwindigkeitspunkten; die Lücke zählt nicht.
    expect(a.movingSec, 898);
    expect(a.stoppedShare, closeTo(301 / 1199, 0.01));
  });

  test('E-Bike ist Rad', () {
    expect(a.sportDeclared, Sport.cycling);
  });

  test('Verlauf ohne falsche Nullen', () {
    // Punkte ohne Geschwindigkeit tragen den letzten Wert weiter, statt 0 km/h zu melden.
    final gefahren = a.series.where((p) => p.elapsedSec > 0);
    expect(gefahren.every((p) => p.speedKmh == 18.0), isTrue);
    expect(gefahren.every((p) => p.hr >= 140), isTrue);
  });
}

class _Punkt {
  const _Punkt(this.t, {this.hr, this.speed});
  final int t;
  final int? hr;
  final double? speed;
}

/// Baut eine minimale FIT-Datei: Kopf, zwei Satztypen für Messpunkte, eine Sitzung.
/// Die Prüfsumme bleibt null — der Leser prüft sie nicht.
Uint8List _fit({
  required int sport,
  required List<_Punkt> punkte,
  required int elapsedSec,
  required int timerSec,
}) {
  const basis = 1159189621; // FIT-Zeit, 24.09.2026 nachmittags
  final d = BytesBuilder();
  void u8(int v) => d.addByte(v & 0xFF);
  void u16(int v) => d.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  void u32(int v) => d.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void definition(int local, int global, List<List<int>> felder) {
    u8(0x40 | local);
    u8(0);
    u8(0); // little endian
    u16(global);
    u8(felder.length);
    for (final f in felder) {
      f.forEach(u8);
    }
  }

  // local 0: record mit Zeit + Puls, local 1: record mit Zeit + Geschwindigkeit.
  definition(0, 20, [[253, 4, 0x86], [3, 1, 0x02]]);
  definition(1, 20, [[253, 4, 0x86], [6, 2, 0x84]]);
  for (final p in punkte) {
    if (p.hr != null) {
      u8(0);
      u32(basis + p.t);
      u8(p.hr!);
    } else {
      u8(1);
      u32(basis + p.t);
      u16((p.speed! * 1000).round());
    }
  }
  // local 2: session mit Sportart, Gesamt- und Fahrzeit.
  definition(2, 18, [[253, 4, 0x86], [5, 1, 0x00], [7, 4, 0x86], [8, 4, 0x86]]);
  u8(2);
  u32(basis + elapsedSec);
  u8(sport);
  u32(elapsedSec * 1000);
  u32(timerSec * 1000);

  final daten = d.toBytes();
  final kopf = BytesBuilder()
    ..addByte(14)
    ..addByte(0x10)
    ..add((ByteData(2)..setUint16(0, 2100, Endian.little)).buffer.asUint8List())
    ..add((ByteData(4)..setUint32(0, daten.length, Endian.little)).buffer.asUint8List())
    ..add('.FIT'.codeUnits)
    ..add([0, 0]);
  return Uint8List.fromList([...kopf.toBytes(), ...daten, 0, 0]);
}
