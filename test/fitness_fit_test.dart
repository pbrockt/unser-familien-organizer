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
      // Der eigentliche Gewinn dieser Dateien: Watt stehen in keiner der Rad-CSVs.
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
