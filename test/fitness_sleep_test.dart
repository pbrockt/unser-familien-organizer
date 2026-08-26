import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_sleep.dart';
import 'package:family_planner/features/fitness/fitness_sport_hint.dart';
import 'package:flutter_test/flutter_test.dart';

HealthDay nacht(
  String datum, {
  required double gesamt,
  double? tief,
  double? rem,
  double? wach,
  String? zuBett,
}) =>
    HealthDay(
      date: datum,
      sleepHours: gesamt,
      sleepDeepHours: tief,
      sleepRemHours: rem,
      sleepAwakeHours: wach,
      bedtime: zuBett,
    );

void main() {
  group('Schlafphasen', () {
    test('rechnet Anteile und Effizienz', () {
      final s = SleepAnalysis.summarize([
        nacht('2026-08-25', gesamt: 8.0, tief: 1.2, rem: 1.6, wach: 0.8),
      ]);
      final n = s.nights.single;
      expect(n.deepShare, closeTo(0.15, 0.001));
      expect(n.remShare, closeTo(0.20, 0.001));
      expect(n.efficiency, closeTo(0.90, 0.001));
    });

    test('erkennt lange Nächte mit wenig Tiefschlaf', () {
      // Der echte Fall aus den Daten: 8,05 h im Bett, 0,38 h Tiefschlaf, 1,43 h wach.
      final s = SleepAnalysis.summarize([
        nacht('2026-08-25', gesamt: 8.05, tief: 0.38, rem: 0.77, wach: 1.43),
      ]);
      expect(s.avgDeepShare!, lessThan(0.06));
      expect(
        SleepAnalysis.insights(s),
        contains(startsWith('Nur 5 % Tiefschlaf')),
      );
    });

    test('kommt ohne Phasendaten klar', () {
      final s = SleepAnalysis.summarize([nacht('2026-08-20', gesamt: 7.0)]);
      expect(s.hasData, isTrue);
      expect(s.avgDeepShare, isNull);
      expect(s.nights.single.hasPhases, isFalse);
    });

    test('ohne Schlafdaten gibt es nichts', () {
      final s = SleepAnalysis.summarize(const [HealthDay(date: '2026-08-20')]);
      expect(s.hasData, isFalse);
      expect(SleepAnalysis.insights(s), isEmpty);
    });
  });

  group('Zubettgeh-Rhythmus', () {
    test('erkennt einen gleichmäßigen Rhythmus', () {
      final s = SleepAnalysis.summarize([
        nacht('2026-08-20', gesamt: 7, zuBett: '22:50'),
        nacht('2026-08-21', gesamt: 7, zuBett: '23:00'),
        nacht('2026-08-22', gesamt: 7, zuBett: '23:10'),
      ]);
      expect(s.typicalBedtime, '23:00');
      expect(s.bedtimeSpreadMinutes!, lessThanOrEqualTo(10));
    });

    test('rechnet über Mitternacht hinweg richtig', () {
      // 23:50 und 00:10 liegen zwanzig Minuten auseinander, nicht dreiundzwanzig
      // Stunden — ohne diese Behandlung wäre die Streuung absurd groß.
      final s = SleepAnalysis.summarize([
        nacht('2026-08-20', gesamt: 7, zuBett: '23:50'),
        nacht('2026-08-21', gesamt: 7, zuBett: '00:10'),
        nacht('2026-08-22', gesamt: 7, zuBett: '00:00'),
      ]);
      expect(s.bedtimeSpreadMinutes!, lessThan(20));
      expect(s.typicalBedtime, '00:00');
    });

    test('meldet starke Schwankung', () {
      // Der echte Fall: 17:07 an einem Tag, 22:03 am nächsten.
      final s = SleepAnalysis.summarize([
        nacht('2026-08-23', gesamt: 7, zuBett: '22:00'),
        nacht('2026-08-24', gesamt: 7, zuBett: '22:03'),
        nacht('2026-08-25', gesamt: 8, zuBett: '17:07'),
      ]);
      expect(s.bedtimeSpreadMinutes!, greaterThan(90));
      expect(
        SleepAnalysis.insights(s).join(' '),
        contains('schwankt'),
      );
    });

    test('braucht mindestens drei Nächte für eine Aussage', () {
      final s = SleepAnalysis.summarize([
        nacht('2026-08-24', gesamt: 7, zuBett: '22:00'),
        nacht('2026-08-25', gesamt: 7, zuBett: '23:00'),
      ]);
      expect(s.bedtimeSpreadMinutes, isNull);
    });
  });

  group('Sportart aus Begleitdatei', () {
    test('liest die TCX-Angabe', () {
      expect(
        SportHint.parse('<Activity Sport="Biking"><Id>2026-08-25</Id>'),
        Sport.cycling,
      );
      expect(SportHint.parse('<Activity Sport="Running">'), Sport.running);
    });

    test('liest die JSON-Angabe', () {
      expect(
        SportHint.parse('"TAGS":{"Data":"TDS","Sport":"bike","Workout Code":" "}'),
        Sport.cycling,
      );
    });

    test('ordnet Unbekanntes lieber gar nicht zu', () {
      // Lieber wieder schätzen als falsch einsortieren.
      expect(SportHint.parse('<Activity Sport="Other">'), isNull);
      expect(SportHint.parse('"Sport":"walking"'), isNull);
      expect(SportHint.parse('kein Hinweis enthalten'), isNull);
    });

    test('findet die Begleitdateien zum CSV-Namen', () {
      expect(
        SportHint.companionNames('2026-08-25_190102.csv'),
        ['2026-08-25_190102.tcx', '2026-08-25_190102.json'],
      );
    });
  });
}
