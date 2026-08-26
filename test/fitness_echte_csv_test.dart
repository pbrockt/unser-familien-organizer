import 'dart:io';

import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ausschnitt einer echten Radfahrt-CSV des Trackers (64 Spalten, Start-, Mittel- und
/// Endabschnitt). Gegen simulierte Daten lässt sich vieles nicht prüfen — etwa dass
/// `time` in UTC steht, dass ein Dutzend Spalten leer ist und dass zwei Dutzend
/// Sensor-Doppelspalten mitlaufen.
void main() {
  const parser = CsvParser();
  late Activity a;

  setUpAll(() {
    final text =
        File('test/fixtures/radfahrt_ausschnitt.csv').readAsStringSync();
    a = parser.parse(text, '2026-08-25_190102.csv')!;
  });

  group('Echte Radfahrt-CSV', () {
    test('wird überhaupt erkannt', () {
      expect(a.date, '2026-08-25');
      expect(a.distanceKm, greaterThan(0));
      expect(a.hrAvg, inInclusiveRange(100, 200));
    });

    test('nutzt die Ortszeit, nicht die UTC-Spalte', () {
      // In der Datei steht time=17:01 (UTC) und TIME_OF_DAY=19:01 (Ortszeit).
      final ohneZeitImNamen = parser.parse(
        File('test/fixtures/radfahrt_ausschnitt.csv').readAsStringSync(),
        'radfahrt.csv',
      )!;
      expect(ohneZeitImNamen.timeOfDay, '19:01',
          reason: 'TIME_OF_DAY muss die UTC-Spalte schlagen');
    });

    test('erkennt Radfahren sicher', () {
      expect(a.sportDetected, Sport.cycling);
      // Über die Spitzengeschwindigkeit, nicht über die knappe Entfaltung von ~4,2 m.
      expect(a.sportConfidence, greaterThan(0.9));
      expect(a.speedMaxKmh, greaterThan(25));
    });

    test('liest Höhenmeter aus den kumulativen Spalten', () {
      // ASCENT/DESCENT laufen monoton hoch; der letzte Wert ist die Summe.
      expect(a.elevGain, inInclusiveRange(0, 50));
      expect(a.elevLoss, inInclusiveRange(0, 50));
    });

    test('trennt Gesamtschnitt und Schnitt in Bewegung', () {
      expect(a.speedAvgKmh, greaterThan(0));
      expect(a.speedMovingAvgKmh, greaterThanOrEqualTo(a.speedAvgKmh),
          reason: 'Ohne Standzeit kann der Schnitt nur höher liegen');
    });

    test('findet die Strecke', () {
      expect(a.hasTrack, isTrue);
      final erster = a.series.firstWhere((p) => p.lat != null);
      expect(erster.lat!, inInclusiveRange(49.0, 50.0));
      expect(erster.lon!, inInclusiveRange(7.0, 8.0));
    });
  });

  group('Kanal-Hygiene', () {
    test('wirft laufende Nummern raus', () {
      // _id, TIME_ACTIVE, TIME_LAP und TIME_TOTAL zählen nur die Zeilen mit.
      for (final zaehler in ['_id', 'TIME_ACTIVE', 'TIME_LAP', 'TIME_TOTAL']) {
        expect(a.channels.containsKey(zaehler), isFalse,
            reason: '$zaehler ist eine laufende Nummer, kein Messwert');
      }
    });

    test('wirft konstante Spalten raus', () {
      // LAP_NR steht die ganze Fahrt auf 1.
      expect(a.channels.containsKey('LAP_NR'), isFalse);
    });

    test('wirft leere Spalten raus', () {
      for (final leer in ['CALORIES', 'POWER', 'TORQUE', 'STRIDES', 'TEMPERATURE']) {
        expect(a.channels.containsKey(leer), isFalse);
      }
    });

    test('wirft Sensor-Doppelspalten raus, die dasselbe liefern', () {
      expect(a.channels.containsKey('HR (HUAWEI Band HR-B54)'), isFalse,
          reason: 'Identisch zur generischen HR-Spalte');
      expect(a.channels.containsKey('ALTITUDE (Smartphone GPS (Satellit))'), isFalse);
      final doppelte =
          a.channels.keys.where((k) => k.contains('(') && k.contains(')')).toList();
      expect(doppelte.length, lessThan(6),
          reason: 'Es blieben zu viele Doppelspalten übrig: $doppelte');
    });

    test('behält die echten Messwerte', () {
      // Das sind die Spalten, die dieser Tracker tatsächlich sinnvoll füllt.
      expect(a.channels.keys, containsAll(['ACCURACY', 'BEARING', 'SLOPE']));
      final slope = a.channels['SLOPE']!;
      expect(slope.min, lessThan(0), reason: 'Gefälle');
      expect(slope.max, greaterThan(0), reason: 'Steigung');
    });

    test('lässt eine überschaubare Zahl an Kanälen übrig', () {
      // Aus 64 Spalten dürfen keine 50 „weiteren Messwerte" werden.
      expect(a.channels.length, lessThan(12),
          reason: 'Übrig: ${a.channels.keys.toList()}');
      expect(a.channels, isNotEmpty);
    });
  });
}
