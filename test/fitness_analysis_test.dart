import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/features/fitness/fitness_analysis.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';

Activity buildActivity({
  required int hrAvg,
  required double stoppedShare,
  int? hrBin,
  int seconds = 3600,
  int movingSec = 0,
  String id = 't.csv',
  String date = '2026-08-25',
  double speedAvgKmh = 20.0,
}) {
  final hist = List<int>.filled(hrHistogramSize, 0);
  hist[hrBin ?? hrAvg] = seconds;
  return Activity(
    id: id,
    date: date,
    timeOfDay: '19:00',
    sportDetected: Sport.cycling,
    sportConfidence: 1,
    durationSec: seconds,
    movingSec: movingSec,
    distanceKm: 20.0,
    hrAvg: hrAvg,
    hrMax: hrAvg,
    hrHistogram: hist,
    cadenceAvg: 80,
    speedAvgKmh: speedAvgKmh,
    speedMaxKmh: 30.0,
    elevGain: 0,
    elevLoss: 0,
    series: const [],
    stoppedShare: stoppedShare,
  );
}

void main() {
  const zones = HrZones.standard;

  group('Kadenz-Bewertung', () {
    test('bewertet die Trittfrequenz beim Radfahren', () {
      expect(Analysis.cadenceCheck(Sport.cycling, 60).verdict, Verdict.low);
      expect(Analysis.cadenceCheck(Sport.cycling, 85).verdict, Verdict.good);
      expect(Analysis.cadenceCheck(Sport.cycling, 105).verdict, Verdict.high);
      expect(Analysis.cadenceCheck(Sport.cycling, 0).verdict, Verdict.noData);
    });

    test('rechnet eine pro Bein gezählte Laufkadenz hoch', () {
      final c = Analysis.cadenceCheck(Sport.running, 87);
      expect(c.perLeg, isTrue);
      expect(c.effectiveValue, 174);
      expect(c.verdict, Verdict.good);
    });

    test('bewertet eine echte Schrittfrequenz ohne Verdopplung', () {
      final c = Analysis.cadenceCheck(Sport.running, 174);
      expect(c.perLeg, isFalse);
      expect(c.effectiveValue, 174);
      expect(c.verdict, Verdict.good);
    });

    test('formatiert Pace und Dauer', () {
      expect(Analysis.formatPace(330), '5:30 min/km');
      expect(Analysis.formatPace(0), '—');
      expect(Analysis.formatDuration(3900), '1:05:00');
      expect(Analysis.formatDuration(2550), '42:30');
    });
  });

  group('Art der Einheit', () {
    test('viel Zeit im harten Bereich ergibt Intensiv', () {
      expect(
        SessionClassifier.suggest(
            buildActivity(hrAvg: 155, stoppedShare: 0), zones),
        SessionType.intensiv,
      );
    });

    test('niedriger Puls mit vielen Pausen ergibt Ausflug', () {
      expect(
        SessionClassifier.suggest(
            buildActivity(hrAvg: 100, stoppedShare: 0.35), zones),
        SessionType.ausflug,
      );
    });

    test('niedriger Puls ohne Pausen bleibt Training', () {
      // Grundlagentraining: ruhiger Puls, aber durchgefahren.
      expect(
        SessionClassifier.suggest(
            buildActivity(hrAvg: 100, stoppedShare: 0.02), zones),
        SessionType.training,
      );
    });

    test('viele Pausen bei höherem Puls bleiben Training', () {
      // Stadtverkehr mit Ampeln ist kein Familienausflug.
      expect(
        SessionClassifier.suggest(
            buildActivity(hrAvg: 135, stoppedShare: 0.35), zones),
        SessionType.training,
      );
    });

    test('Belastung gewichtet die Zonen nach Intensität', () {
      // 60 min je Zone: 60*1 + 60*2 + 60*3 + 60*4 = 600
      expect(
        SessionClassifier.loadScoreFromZones([3600, 3600, 3600, 3600]),
        600,
      );
    });
  });

  group('Summarizer', () {
    test('Ausflüge fallen aus den Trends heraus', () {
      // Zwei zügige Trainings, dann ein langsamer Ausflug. Ohne Ausschluss würde der
      // Tempo-Trend negativ — obwohl die Form sich nicht verschlechtert hat.
      final list = [
        buildActivity(
            hrAvg: 130, stoppedShare: 0, id: 'a.csv', date: '2026-08-01', speedAvgKmh: 24),
        buildActivity(
            hrAvg: 130, stoppedShare: 0, id: 'b.csv', date: '2026-08-02', speedAvgKmh: 26),
        buildActivity(
            hrAvg: 130, stoppedShare: 0.4, id: 'c.csv', date: '2026-08-03', speedAvgKmh: 12),
      ];

      final ohne = Summarizer.summarize(Sport.cycling, list, zones)!;
      expect(ohne.speedTrend, lessThan(0),
          reason: 'Ohne Einstufung zieht der Ausflug den Trend nach unten');

      final mit = Summarizer.summarize(
        Sport.cycling,
        list,
        zones,
        typeOf: (a) => a.id == 'c.csv' ? SessionType.ausflug : SessionType.training,
      )!;
      expect(mit.excludedFromTrends, 1);
      expect(mit.trendBasis, 2);
      expect(mit.speedTrend, greaterThan(0),
          reason: 'Mit Einstufung bleibt der Trend positiv');
      expect(mit.count, 3, reason: 'Distanz zählt trotzdem voll');
    });

    test('Fahrten mit Motor fallen aus den Trends heraus', () {
      // Zwei Fahrten aus eigener Kraft, dann eine mit Motor. Ohne Ausschluss meldete die
      // App einen Tempozuwachs, den der Motor gefahren hat und nicht die Form.
      final list = [
        buildActivity(
            hrAvg: 130, stoppedShare: 0, id: 'a.csv', date: '2026-08-01', speedAvgKmh: 22),
        buildActivity(
            hrAvg: 130, stoppedShare: 0, id: 'b.csv', date: '2026-08-02', speedAvgKmh: 21),
        buildActivity(
            hrAvg: 130, stoppedShare: 0, id: 'e.csv', date: '2026-08-03', speedAvgKmh: 32),
      ];

      final ohne = Summarizer.summarize(Sport.cycling, list, zones)!;
      expect(ohne.speedTrend, greaterThan(0),
          reason: 'Ohne Angabe hebt der Motor den Trend');

      final mit = Summarizer.summarize(
        Sport.cycling,
        list,
        zones,
        ebikeOf: (a) => a.id == 'e.csv',
      )!;
      expect(mit.ebikeCount, 1);
      expect(mit.excludedFromTrends, 1);
      expect(mit.trendBasis, 2);
      expect(mit.speedTrend, lessThan(0), reason: 'Übrig bleiben 22 und 21 km/h');
      expect(mit.count, 3, reason: 'Distanz und Belastung zählen trotzdem voll');
      expect(mit.totalKm, 60);
    });

    test('nennt Ausflug und Motor getrennt', () {
      final list = [
        buildActivity(hrAvg: 130, stoppedShare: 0, id: 'a.csv', date: '2026-08-01'),
        buildActivity(hrAvg: 130, stoppedShare: 0, id: 'x.csv', date: '2026-08-02'),
        buildActivity(hrAvg: 130, stoppedShare: 0, id: 'e.csv', date: '2026-08-03'),
      ];
      final s = Summarizer.summarize(
        Sport.cycling,
        list,
        zones,
        typeOf: (a) => a.id == 'x.csv' ? SessionType.ausflug : SessionType.training,
        ebikeOf: (a) => a.id == 'e.csv',
      )!;

      expect(s.tripCount, 1);
      expect(s.ebikeCount, 1);
      expect(s.excludedFromTrends, 2);
      final texte = Summarizer.insights(s, zones);
      expect(texte.any((t) => t.contains('als Ausflug eingestuft')), isTrue);
      expect(texte.any((t) => t.contains('Motorunterstützung')), isTrue);
    });

    test('zählt eine Fahrt nur einmal, wenn sie Ausflug und Motor ist', () {
      final list = [
        buildActivity(hrAvg: 130, stoppedShare: 0, id: 'a.csv', date: '2026-08-01'),
        buildActivity(hrAvg: 130, stoppedShare: 0, id: 'b.csv', date: '2026-08-02'),
      ];
      final s = Summarizer.summarize(
        Sport.cycling,
        list,
        zones,
        typeOf: (a) => a.id == 'b.csv' ? SessionType.ausflug : SessionType.training,
        ebikeOf: (a) => a.id == 'b.csv',
      )!;

      expect(s.excludedFromTrends, 1);
      expect(s.trendBasis, 1);
    });

    test('summiert die Zeit in Bewegung, nicht die Uhrzeit', () {
      final gemessen = Summarizer.summarize(
        Sport.cycling,
        [buildActivity(hrAvg: 130, stoppedShare: 0.5, seconds: 3600, movingSec: 1800)],
        zones,
      )!;
      expect(gemessen.totalSec, 1800);

      // Ohne gemessene Bewegungszeit bleibt es bei der Gesamtzeit.
      final ohne = Summarizer.summarize(
        Sport.cycling,
        [buildActivity(hrAvg: 130, stoppedShare: 0.5, seconds: 3600)],
        zones,
      )!;
      expect(ohne.totalSec, 3600);
    });

    test('liefert für eine leere Liste nichts', () {
      expect(Summarizer.summarize(Sport.cycling, const [], zones), isNull);
    });

    test('meldet bei einer einzelnen Einheit keinen Trend', () {
      final s = Summarizer.summarize(
          Sport.cycling, [buildActivity(hrAvg: 130, stoppedShare: 0)], zones)!;
      expect(s.speedTrend, 0);
      expect(s.trendBasis, 1);
      expect(
        Summarizer.insights(s, zones),
        contains(startsWith('Ab der zweiten vergleichbaren Einheit')),
      );
    });
  });
}
