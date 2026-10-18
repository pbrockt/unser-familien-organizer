import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_parsers.dart';
import 'package:family_planner/features/fitness/health_connect_mapping.dart';
import 'package:family_planner/features/fitness/health_connect_track.dart';
import 'package:flutter_test/flutter_test.dart';

HcSample _wert(HcKind k, DateTime t, double v, {String q = 'Huawei Health'}) =>
    HcSample(kind: k, from: t, to: t, value: v, source: q);

void main() {
  final start = DateTime(2026, 10, 18, 15, 30);
  // 40 Minuten: 15 fahren mit 5 m/s, 10 Minuten Pause ohne jeden Messwert (die Uhr
  // pausiert automatisch), 15 fahren mit 6 m/s.
  final fahrt = HcTraining(
    from: start,
    to: start.add(const Duration(minutes: 40)),
    type: 'BIKING',
    source: 'Huawei Health',
    distanceM: 9900,
  );
  List<HcSample> tempoUndPuls() => [
        for (var s = 0; s < 15 * 60; s += 5) ...[
          _wert(HcKind.speed, start.add(Duration(seconds: s)), 5),
          _wert(HcKind.heartRate, start.add(Duration(seconds: s)), 130),
        ],
        for (var s = 25 * 60; s < 40 * 60; s += 5) ...[
          _wert(HcKind.speed, start.add(Duration(seconds: s)), 6),
          _wert(HcKind.heartRate, start.add(Duration(seconds: s)), 150),
        ],
      ];
  // Eine Strecke mit Höhe: nach Osten, 50 m Anstieg.
  HcRoute strecke() => HcRoute(
        from: start,
        to: fahrt.to,
        points: [
          for (var s = 0; s < 15 * 60; s += 2)
            HcRoutePoint(
              time: start.add(Duration(seconds: s)),
              lat: 49.76,
              lon: 7.69 + s * 0.00007,
              altitude: 200 + s / 18,
            ),
        ],
      );

  test('Dateiname: Datum, Uhrzeit, Sportart, Herkunft', () {
    expect(trainingTrackFileName(fahrt), '2026-10-18_153000_rad_hc.csv');
  });

  test('der normale CSV-Leser macht daraus eine vollständige Fahrt', () {
    final csv = trainingTrackCsv(
      training: fahrt,
      samples: tempoUndPuls(),
      routes: [strecke()],
    )!;
    final a = const CsvParser().parse(csv, trainingTrackFileName(fahrt))!;
    expect(a.sportEffective, Sport.cycling);
    expect(a.date, '2026-10-18');
    expect(a.timeOfDay, '15:30');
    expect(a.durationSec, closeTo(40 * 60, 2));
    // 15 min × 5 m/s + 15 min × 6 m/s = 9,9 km.
    expect(a.distanceKm, closeTo(9.9, 0.05));
    // Die Pause ist Stand, nicht Fahrt mit dem letzten Tempo.
    expect(a.movingSec, closeTo(30 * 60, 15));
    expect(a.stoppedShare, closeTo(0.25, 0.02));
    expect(a.hrMax, 150);
    expect(a.hasTrack, isTrue);
    expect(a.elevGain, closeTo(50, 2));
  });

  test('ohne Tempowerte: Tempo aus der GPS-Strecke', () {
    final csv = trainingTrackCsv(
      training: fahrt,
      samples: [
        for (final s in tempoUndPuls())
          if (s.kind == HcKind.heartRate) s,
      ],
      routes: [strecke()],
    )!;
    final a = const CsvParser().parse(csv, trainingTrackFileName(fahrt))!;
    // 0,00014° Länge je 2 s bei 49,76° Breite ≈ 5 m/s.
    expect(a.speedMovingAvgKmh, closeTo(18, 1.5));
    expect(a.hasTrack, isTrue);
  });

  test('nur Puls, kein Tempo und keine Strecke: keine Datei', () {
    expect(
      trainingTrackCsv(
        training: fahrt,
        samples: [
          for (final s in tempoUndPuls())
            if (s.kind == HcKind.heartRate) s,
        ],
      ),
      isNull,
    );
  });

  group('Rangfolge bei derselben Fahrt', () {
    Activity einheit(String id, String uhr) => Activity(
          id: id,
          date: '2026-10-18',
          timeOfDay: uhr,
          sportDetected: Sport.cycling,
          sportConfidence: 1,
          durationSec: 2400,
          distanceKm: 10,
          hrAvg: 140,
          hrMax: 150,
          hrHistogram: List<int>.filled(hrHistogramSize, 0),
          cadenceAvg: 0,
          speedAvgKmh: 15,
          speedMaxKmh: 22,
          elevGain: 0,
          elevLoss: 0,
          series: const [],
        );
    final bosch = einheit('bosch.fit', '15:32');
    final verlauf = einheit('2026-10-18_153000_rad_hc.csv', '15:30');
    final zusammen = einheit('hc:2026-10-18 15:30:00', '15:30');

    test('Radcomputer vor Verlauf vor Zusammenfassung', () {
      expect(withoutHcDuplicates([zusammen, verlauf, bosch]).map((a) => a.id), ['bosch.fit']);
    });

    test('ohne Radcomputer gewinnt der Verlauf', () {
      expect(
        withoutHcDuplicates([zusammen, verlauf]).map((a) => a.id),
        ['2026-10-18_153000_rad_hc.csv'],
      );
    });

    test('eine andere Fahrt am selben Tag bleibt', () {
      expect(withoutHcDuplicates([verlauf, einheit('morgens.fit', '07:00')]), hasLength(2));
    });
  });
}
