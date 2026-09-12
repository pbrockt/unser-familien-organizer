import 'dart:io';
import 'dart:typed_data';

import 'package:family_planner/features/fitness/fitness_analysis.dart';
import 'package:family_planner/features/fitness/fitness_fit_parser.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Echte Datei aus MyWhoosh, 12.09.2026: 21 Minuten auf der Rolle, 1281 Messpunkte im
/// Sekundentakt, neun Runden als Leistungsrampe.
///
/// Gegen die echte Datei geprüft und nicht gegen eine gebaute: Das Format ist
/// selbstbeschreibend, und eine selbst erzeugte Datei würde genau die Annahmen bestätigen,
/// die der Leser ohnehin trifft.
void main() {
  const parser = FitParser();
  final bytes = Uint8List.fromList(
    File('test/fixtures/mywhoosh_einheit.fit').readAsBytesSync(),
  );

  group('MyWhoosh-Datei', () {
    late final Activity a;

    setUpAll(() => a = parser.parse(bytes, 'mywhoosh.fit')!);

    test('erkennt Sportart und Ort aus der Datei', () {
      expect(a.sportDetected, Sport.cycling);
      expect(a.sportDeclared, Sport.cycling,
          reason: 'Die Datei nennt die Sportart — geraten wird hier nichts');
      expect(a.sportConfidence, 1.0);
      expect(a.indoor, isTrue, reason: 'Unterart virtual_activity');
    });

    test('liest Datum und Uhrzeit in Ortszeit', () {
      // Die Datei speichert UTC. 12:43:10 UTC ist im Sommer 14:43 Ortszeit.
      final erwartet = DateTime.utc(2026, 9, 12, 12, 43, 10).toLocal();
      expect(a.date,
          '${erwartet.year}-${erwartet.month.toString().padLeft(2, '0')}-'
          '${erwartet.day.toString().padLeft(2, '0')}');
      expect(
        a.timeOfDay,
        '${erwartet.hour.toString().padLeft(2, '0')}:'
        '${erwartet.minute.toString().padLeft(2, '0')}',
      );
    });

    test('liest die Kennzahlen der Einheit', () {
      expect(a.durationSec, 1281);
      expect(a.distanceKm, closeTo(10.02, 0.01));
      expect(a.hrAvg, 117);
      expect(a.hrMax, 146);
      expect(a.cadenceAvg, 54);
      expect(a.speedAvgKmh, closeTo(28.2, 0.1));
      expect(a.elevGain, 128);
    });

    test('liest die Leistung', () {
      expect(a.powerAvg, 272);
      expect(a.powerMax, 447);
      expect(a.channels['POWER'], isNotNull);
      expect(a.channels['POWER']!.max, 447);
      expect(a.series.every((p) => p.extra.containsKey('POWER')), isTrue);
    });

    test('durchgetreten heißt kaum Standzeit', () {
      expect(a.movingSec, 1280);
      expect(a.stoppedShare, lessThan(0.01));
    });

    test('rechnet den Verlauf herunter, behält aber die Form', () {
      expect(a.series.length, inInclusiveRange(90, 101));
      expect(a.series.first.elapsedSec, 0);
      expect(a.series.last.elapsedSec, greaterThan(1200));
      expect(a.series.map((p) => p.hr).reduce((x, y) => x > y ? x : y),
          greaterThan(130));
    });

    test('lässt die Koordinaten der virtuellen Welt weg', () {
      // Die Datei trägt Positionen in Japan. Eine Karte daraus wäre eine Behauptung
      // über eine Fahrt, die im Wohnzimmer stattfand.
      expect(a.hasTrack, isFalse);
      expect(a.series.every((p) => p.lat == null && p.lon == null), isTrue);
    });

    test('liest die neun Runden mit ihrer Leistung', () {
      expect(a.laps, hasLength(9));
      final erste = a.laps.first;
      expect(erste.number, 1);
      expect(erste.durationSec, 180);
      expect(erste.distanceKm, closeTo(0.87, 0.01));
      expect(erste.avgSpeedKmh, closeTo(17.2, 0.1));
      expect(erste.avgHr, 98);
      expect(erste.maxHr, 108);
      expect(erste.avgCadence, 41);
      expect(erste.avgPower, 207);
      expect(erste.maxPower, 281);
    });

    test('bildet die Rampe der Runden ab', () {
      // Minutenstufen mit steigender Leistung — daran hängt, ob die Runden überhaupt
      // etwas wert sind. Runde 5 ist die Spitze, danach kommt Erholung.
      final watt = a.laps.map((l) => l.avgPower).toList();
      expect(watt.sublist(0, 5), [207, 232, 258, 320, 420]);
      expect(watt[5], lessThan(watt[4]));
    });

    test('füllt das Puls-Histogramm für die Belastungsrechnung', () {
      final summe = a.hrHistogram.fold<int>(0, (s, v) => s + v);
      expect(summe, greaterThan(1200), reason: 'gut eine Sekunde je Messpunkt');
      expect(SessionClassifier.loadScore(a, HrZones.standard), greaterThan(0));
    });

    test('überlebt den Weg durch den Zwischenspeicher', () {
      final wieder = Activity.fromJson(a.toJson());
      expect(wieder.powerAvg, a.powerAvg);
      expect(wieder.indoor, isTrue);
      expect(wieder.laps, hasLength(9));
      expect(wieder.laps[4].avgPower, 420);
      expect(wieder.movingSec, a.movingSec);
    });
  });

  group('Gerechnete Leistung erkennen', () {
    // In beiden MyWhoosh-Dateien ist die Leistung schlicht die Trittfrequenz mal 5,03 —
    // ein festes Drehmoment von 48 Nm über die ganze Einheit, auch während sich die
    // Leistung verdoppelt. So tritt kein Mensch. Dazu kommen nur 48 verschiedene
    // Wattwerte auf 1281 Messpunkte, alle auf einem 5-Watt-Raster. Zusammen ist das
    // keine Messung, sondern eine Rechnung.
    test('erkennt sie in der langen Einheit', () {
      final a = parser.parse(bytes, 'lang.fit')!;
      expect(a.powerDerived, isTrue);
      expect(a.powerAvg, 272);
    });

    test('erkennt sie auch in der kurzen Einheit', () {
      final kurz = Uint8List.fromList(
        File('test/fixtures/mywhoosh_kurz.fit').readAsBytesSync(),
      );
      final a = parser.parse(kurz, 'kurz.fit')!;
      expect(a.powerDerived, isTrue);
      expect(a.powerAvg, 270);
      expect(a.laps, isEmpty, reason: 'Eine einzige Runde ist keine Struktur');
      expect(a.durationSec, 438);
    });

    test('bleibt bei einem echten Leistungsmesser aus', () {
      // Gestreute Verhältnisse, wie sie entstehen, wenn Watt und Trittfrequenz
      // unabhängig gemessen werden: mal hart am Berg bei 60/min, mal locker bei 95.
      final echt = [
        for (var i = 0; i < 600; i++) 2.0 + (i % 71) * 0.09,
      ];
      expect(FitParser.powerLooksDerived(echt, 380), isFalse);
    });

    test('bleibt aus, wenn nur das Verhältnis eng ist', () {
      // Gleichmäßig getretene Einheit mit echtem Messgerät: Das Verhältnis ist eng,
      // aber die Werte füllen den Bereich. Ein Merkmal allein darf nicht reichen.
      final gleichmaessig = [
        for (var i = 0; i < 600; i++) 5.0 + (i % 7) * 0.005,
      ];
      expect(FitParser.powerLooksDerived(gleichmaessig, 320), isFalse);
    });

    test('bleibt aus, wenn nur das Raster grob ist', () {
      // Wenige verschiedene Werte, aber gestreutes Verhältnis — etwa ein stark
      // geglätteter Messwert.
      final gestreut = [
        for (var i = 0; i < 600; i++) 2.0 + (i % 53) * 0.12,
      ];
      expect(FitParser.powerLooksDerived(gestreut, 40), isFalse);
    });

    test('trifft die Entscheidung nicht bei zu wenigen Punkten', () {
      final wenig = [for (var i = 0; i < 40; i++) 5.02];
      expect(FitParser.powerLooksDerived(wenig, 3), isFalse,
          reason: 'Unter einer Minute wäre jede Aussage Zufall');
    });

    test('bleibt ohne Leistung aus', () {
      expect(parser.parse(bytes, 'x.fit')!.powerDerived, isTrue);
      // Eine Einheit ohne Wattwerte hat nichts zu markieren.
      const ohne = Activity(
        id: 'a',
        date: '2026-09-12',
        timeOfDay: '14:00',
        sportDetected: Sport.cycling,
        sportConfidence: 1,
        durationSec: 600,
        distanceKm: 5,
        hrAvg: 120,
        hrMax: 140,
        hrHistogram: [],
        cadenceAvg: 80,
        speedAvgKmh: 25,
        speedMaxKmh: 30,
        elevGain: 0,
        elevLoss: 0,
        series: [],
      );
      expect(ohne.powerDerived, isFalse);
    });
  });

  group('Kaputte Eingaben', () {
    test('weist an, was keine FIT-Datei ist', () {
      expect(parser.parse(Uint8List.fromList(List.filled(64, 0)), 'x.fit'), isNull);
      expect(parser.parse(Uint8List(0), 'leer.fit'), isNull);
    });

    test('gibt bei einer abgeschnittenen Datei auf, statt zu werfen', () {
      // Abgebrochene Übertragung: Der Kopf verspricht mehr, als die Datei hergibt.
      final halb = Uint8List.fromList(bytes.sublist(0, bytes.length ~/ 2));
      expect(() => parser.parse(halb, 'halb.fit'), returnsNormally);
    });

    test('verkraftet Müll hinter dem Kopf', () {
      final kaputt = Uint8List.fromList(bytes);
      for (var i = 20; i < 400; i++) {
        kaputt[i] = 0xAB;
      }
      expect(() => parser.parse(kaputt, 'kaputt.fit'), returnsNormally);
    });
  });
}
