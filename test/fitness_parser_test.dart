import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_parsers.dart';

/// Baut eine CSV im Format des Trackers: alle Felder gequotet, eine Zeile je Sekunde.
/// [speedMps] und [cadence] bleiben konstant, damit die erwarteten Mittelwerte exakt sind.
String buildCsv({
  required int seconds,
  required double speedMps,
  required int cadence,
  required int hr,
  double startAltitude = 10.0,
}) {
  String quote(List<String> fields) => '"${fields.join('","')}"';

  final header = quote([
    'time',
    'ALTITUDE',
    'CADENCE',
    'DISTANCE_m',
    'HR',
    'SPEED_mps',
    'ASCENT',
    'DESCENT',
  ]);

  final rows = List.generate(seconds, (i) {
    final minute = 1 + i ~/ 60;
    final second = i % 60;
    final time = '2026-08-25 19:${minute.toString().padLeft(2, '0')}:'
        '${second.toString().padLeft(2, '0')}';
    return quote([
      time,
      (startAltitude + i * 0.1).toStringAsFixed(1),
      '$cadence',
      (speedMps * i).toStringAsFixed(1),
      '$hr',
      speedMps.toStringAsFixed(3),
      '12',
      '5',
    ]);
  });

  return '$header\n${rows.join('\n')}';
}

void main() {
  const parser = CsvParser();
  const health = HealthParser();

  group('CsvParser', () {
    test('liest Kennzahlen einer Radfahrt korrekt aus', () {
      final csv = buildCsv(seconds: 61, speedMps: 6.944, cadence: 85, hr: 138);
      final a = parser.parse(csv, '2026-08-25_190102.csv');

      expect(a, isNotNull);
      expect(a!.date, '2026-08-25');
      expect(a.timeOfDay, '19:01');
      expect(a.durationSec, 60);
      expect(a.hrAvg, 138);
      expect(a.hrMax, 138);
      expect(a.cadenceAvg, 85);
      expect(a.speedAvgKmh, closeTo(25.0, 0.05));
      // Distanz ist der höchste DISTANCE_m-Wert, hier 6,944 m/s * 60 s.
      expect(a.distanceKm, closeTo(0.4166, 0.001));
      expect(a.elevGain, 12);
      expect(a.elevLoss, 5);
    });

    test('erkennt Radfahren an der Entfaltung', () {
      final csv = buildCsv(seconds: 60, speedMps: 6.944, cadence: 85, hr: 140);
      final a = parser.parse(csv, '2026-08-25_190102.csv')!;
      expect(a.sportDetected, Sport.cycling);
      expect(a.metersPerCycle, greaterThan(4.0));
    });

    test('erkennt Laufen an der Schrittlänge', () {
      final csv = buildCsv(seconds: 60, speedMps: 3.0, cadence: 170, hr: 150);
      final a = parser.parse(csv, '2026-08-26_070000.csv')!;
      expect(a.sportDetected, Sport.running);
    });

    test('erkennt Laufen auch bei pro Bein gezählter Kadenz', () {
      // 85/min sieht wie eine Trittfrequenz aus — erst der Weg pro Zyklus (2,1 m)
      // trennt das sauber vom Radfahren (dort über 4 m).
      final csv = buildCsv(seconds: 60, speedMps: 3.0, cadence: 85, hr: 150);
      final a = parser.parse(csv, '2026-08-26_070000.csv')!;
      expect(a.sportDetected, Sport.running);
    });

    test('Dateiname schlägt die Heuristik', () {
      final csv = buildCsv(seconds: 60, speedMps: 6.944, cadence: 85, hr: 140);
      final a = parser.parse(csv, '2026-08-25_190102_lauf.csv')!;
      expect(a.sportDetected, Sport.running);
      expect(a.sportConfidence, 1.0);
    });

    test('weist eine CSV ohne Pflichtspalten zurück', () {
      expect(parser.parse('"a","b"\n"1","2"', 'x.csv'), isNull);
      expect(parser.parse('', 'leer.csv'), isNull);
    });

    test('nimmt bei doppelten Spalten die erste', () {
      const header = '"time","ALTITUDE","CADENCE","DISTANCE_m","HR","SPEED_mps",'
          '"ASCENT","DESCENT","HR (HUAWEI Band HR-B54)"';
      const row = '"2026-08-25 19:01:00","10","85","100","130","6.9","0","0","999"';
      final a = parser.parse('$header\n$row', '2026-08-25_190100.csv')!;
      expect(a.hrAvg, 130, reason: 'Der generische HR-Wert muss gewinnen');
    });

    test('rechnet den Verlauf auf höchstens 100 Punkte herunter', () {
      final csv = buildCsv(seconds: 600, speedMps: 5.0, cadence: 80, hr: 140);
      final a = parser.parse(csv, '2026-08-25_190102.csv')!;
      expect(a.series.length, inInclusiveRange(90, 101));
    });

    test('hält den Anteil der Standzeit fest', () {
      final csv = buildCsv(seconds: 60, speedMps: 0.0, cadence: 0, hr: 100);
      final a = parser.parse(csv, '2026-08-25_190102.csv')!;
      expect(a.stoppedShare, closeTo(1.0, 0.001));
    });
  });

  group('CSV vollständig auslesen', () {
    String csv(List<String> spalten, List<List<String>> zeilen) {
      String q(List<String> f) => '"${f.join('","')}"';
      return [q(spalten), ...zeilen.map(q)].join('\n');
    }

    const basis = [
      'time', 'ALTITUDE', 'CADENCE', 'DISTANCE_m', 'HR', 'SPEED_mps',
      'ASCENT', 'DESCENT',
    ];

    test('nimmt unbekannte Zahlenspalten als eigene Kanäle mit', () {
      final text = csv(
        [...basis, 'POWER_w', 'TEMPERATURE_c'],
        [
          ['2026-08-25 19:01:00', '10', '85', '0', '130', '6.9', '0', '0', '180', '21.5'],
          ['2026-08-25 19:01:01', '11', '86', '7', '132', '7.0', '1', '0', '220', '21.7'],
        ],
      );
      final a = parser.parse(text, '2026-08-25_190100.csv')!;

      expect(a.channels.keys, containsAll(['POWER_w', 'TEMPERATURE_c']));
      final power = a.channels['POWER_w']!;
      expect(power.min, 180);
      expect(power.max, 220);
      expect(power.avg, closeTo(200, 0.001));
      expect(power.count, 2);
      // Auch im Verlauf, damit sie sich zeichnen lassen.
      expect(a.series.first.extra['POWER_w'], 180);
    });

    test('nimmt auch die sensorspezifischen Doppelspalten mit', () {
      final text = csv(
        [...basis, 'HR (HUAWEI Band HR-B54)'],
        [['2026-08-25 19:01:00', '10', '85', '0', '130', '6.9', '0', '0', '99']],
      );
      final a = parser.parse(text, '2026-08-25_190100.csv')!;
      expect(a.hrAvg, 130, reason: 'Die generische Spalte bleibt maßgeblich');
      expect(a.channels['HR (HUAWEI Band HR-B54)']?.avg, 99);
    });

    test('erkennt Koordinaten und meldet eine Strecke', () {
      final text = csv(
        [...basis, 'LATITUDE', 'LONGITUDE'],
        [
          ['2026-08-25 19:01:00', '10', '85', '0', '130', '6.9', '0', '0', '53.35', '7.58'],
          ['2026-08-25 19:01:01', '11', '86', '7', '132', '7.0', '1', '0', '53.36', '7.59'],
        ],
      );
      final a = parser.parse(text, '2026-08-25_190100.csv')!;
      expect(a.hasTrack, isTrue);
      expect(a.series.first.lat, closeTo(53.35, 0.001));
      expect(a.series.first.lon, closeTo(7.58, 0.001));
      expect(a.channels.containsKey('LATITUDE'), isFalse,
          reason: 'Koordinaten sind kein freier Messkanal');
    });

    test('verwirft Nullkoordinaten', () {
      // 0/0 liegt im Atlantik und ist praktisch immer ein Messfehler.
      final text = csv(
        [...basis, 'lat', 'lon'],
        [['2026-08-25 19:01:00', '10', '85', '0', '130', '6.9', '0', '0', '0', '0']],
      );
      final a = parser.parse(text, '2026-08-25_190100.csv')!;
      expect(a.hasTrack, isFalse);
    });

    test('ohne Koordinatenspalten gibt es keine Strecke', () {
      final text = csv(
        basis,
        [['2026-08-25 19:01:00', '10', '85', '0', '130', '6.9', '0', '0']],
      );
      expect(parser.parse(text, '2026-08-25_190100.csv')!.hasTrack, isFalse);
    });
  });

  group('HealthParser', () {
    const md = '''
---
date: 2026-08-25
steps: 3692
sleep_total_hours: 0.80
active_calories: 91
total_calories: 1655
average_heart_rate: 79
heart_rate_min: 55
heart_rate_max: 131
blood_oxygen_avg: 97
---

Freitext, der ignoriert wird.
''';

    test('liest das Frontmatter aus', () {
      final h = health.parse(md, '2026-08-25.md')!;
      expect(h.date, '2026-08-25');
      expect(h.steps, 3692);
      expect(h.sleepHours, closeTo(0.8, 0.001));
      expect(h.totalCalories, 1655);
      expect(h.hrAvg, 79);
      expect(h.spo2Avg, 97);
    });

    test('übernimmt ein Gewicht aus dem Frontmatter', () {
      final h = health.parse('---\ndate: 2026-08-25\nweight_kg: 90.4\n---', 'x.md')!;
      expect(h.weightKg, closeTo(90.4, 0.001));
    });

    test('fällt auf das Datum im Dateinamen zurück', () {
      final h = health.parse('---\nsteps: 100\n---', '2026-01-02.md')!;
      expect(h.date, '2026-01-02');
    });

    test('weist Dateien ohne Frontmatter zurück', () {
      expect(health.parse('nur text', '2026-08-25.md'), isNull);
    });
  });

  group('HrZones', () {
    test('nutzt ohne HFmax die Standardgrenzen', () {
      expect(HrZones.forMaxHr(null), HrZones.standard);
      expect(HrZones.forMaxHr(0), HrZones.standard);
      expect(HrZones.forMaxHr(60), HrZones.standard,
          reason: 'Unrealistische Werte dürfen die Zonen nicht kaputt machen');
    });

    test('leitet Zonen aus der HFmax ab', () {
      final z = HrZones.forMaxHr(190);
      expect(z.t1, 114);
      expect(z.t2, 143);
      expect(z.t3, 162);
    });

    test('verteilt ein Histogramm auf die Zonen', () {
      final hist = List<int>.filled(hrHistogramSize, 0);
      hist[100] = 10; // Zone 1
      hist[130] = 20; // Zone 2
      hist[150] = 30; // Zone 3
      hist[170] = 40; // Zone 4
      expect(HrZones.standard.distribute(hist), [10, 20, 30, 40]);
      expect(HrZones.standard.hardSharePercent(hist), 70);
    });
  });
}
