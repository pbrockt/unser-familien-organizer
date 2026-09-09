import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_parsers.dart';
import 'package:family_planner/features/fitness/fitness_repository.dart';
import 'package:family_planner/features/fitness/fitness_weekly.dart';
import 'package:flutter_test/flutter_test.dart';

/// Baut eine CSV aus (Sekunde seit Start, Geschwindigkeit in m/s).
///
/// Absichtlich mit ausdrücklichen Zeitpunkten statt einer festen Zeilenzahl: Nur so
/// lassen sich Aufzeichnungslücken nachstellen, und genau die sind der interessante Fall.
String csvMit(List<(int, double)> punkte) {
  String q(List<String> f) => '"${f.join('","')}"';

  final header = q([
    'time',
    'ALTITUDE',
    'CADENCE',
    'DISTANCE_m',
    'HR',
    'SPEED_mps',
    'ASCENT',
    'DESCENT',
  ]);

  final start = DateTime(2026, 8, 25, 19, 1, 0);
  var strecke = 0.0;
  var vorher = 0;

  final zeilen = <String>[];
  for (final (sekunde, tempo) in punkte) {
    strecke += tempo * (sekunde - vorher);
    vorher = sekunde;
    final t = start.add(Duration(seconds: sekunde));
    zeilen.add(q([
      '${t.year}-${_zwei(t.month)}-${_zwei(t.day)} '
          '${_zwei(t.hour)}:${_zwei(t.minute)}:${_zwei(t.second)}',
      '10.0',
      '85',
      strecke.toStringAsFixed(1),
      '130',
      tempo.toStringAsFixed(3),
      '0',
      '0',
    ]));
  }

  return '$header\n${zeilen.join('\n')}';
}

String _zwei(int v) => v.toString().padLeft(2, '0');

/// Punkte für eine durchgehende Aufzeichnung im Sekundentakt.
List<(int, double)> takt(int vonSekunde, int bisSekunde, double tempo) => [
      for (var s = vonSekunde; s <= bisSekunde; s++) (s, tempo),
    ];

Activity fahrt({
  required String datum,
  required int durationSec,
  required int movingSec,
}) =>
    Activity(
      id: '$datum-$durationSec',
      date: datum,
      timeOfDay: '19:00',
      sportDetected: Sport.cycling,
      sportConfidence: 1,
      durationSec: durationSec,
      movingSec: movingSec,
      distanceKm: 10,
      hrAvg: 130,
      hrMax: 150,
      hrHistogram: List<int>.filled(hrHistogramSize, 0),
      cadenceAvg: 80,
      speedAvgKmh: 20,
      speedMaxKmh: 30,
      elevGain: 0,
      elevLoss: 0,
      series: const [],
    );

void main() {
  const parser = CsvParser();

  group('Bewegungszeit aus der CSV', () {
    test('zählt einen Stopp nicht als Fahrzeit', () {
      // Eine Minute fahren, eine Minute an der Ampel, eine Minute fahren.
      final a = parser.parse(
        csvMit([...takt(0, 59, 5), ...takt(60, 119, 0), ...takt(120, 179, 5)]),
        '2026-08-25_190100.csv',
      )!;

      expect(a.durationSec, 179, reason: 'Die Gesamtzeit bleibt die Uhrzeit');
      // 179 Zwischenräume, davon 60 im Stand.
      expect(a.movingSec, 119);
      expect(a.activeSec, 119);
      expect(a.pausedSec, 60);
    });

    test('zählt eine Aufzeichnungslücke weder als Fahrt noch als Ampel', () {
      // Neun Minuten Pause, in denen der Tracker gar nichts geschrieben hat.
      final a = parser.parse(
        csvMit([...takt(0, 59, 5), ...takt(600, 659, 5)]),
        '2026-08-25_190100.csv',
      )!;

      expect(a.durationSec, 659);
      expect(a.movingSec, 118, reason: '2 × 59 Sekunden, die Lücke zählt nicht mit');
      expect(a.pausedSec, 541);
    });

    test('eine durchgefahrene Runde hat keine Standzeit', () {
      final a = parser.parse(csvMit(takt(0, 300, 6)), '2026-08-25_190100.csv')!;

      expect(a.movingSec, 300);
      expect(a.pausedSec, 0);
      expect(a.stoppedShare, closeTo(0, 0.001));
    });

    test('die Standzeit ist ein Anteil der Zeit, nicht der Zeilen', () {
      // Über die Zeilen gezählt wären das 50 % — es sind aber 60 von 179 Sekunden.
      final a = parser.parse(
        csvMit([...takt(0, 59, 5), ...takt(60, 119, 0), ...takt(120, 179, 5)]),
        '2026-08-25_190100.csv',
      )!;
      expect(a.stoppedShare, closeTo(60 / 179, 0.01));
    });

    test('rechnet die Pace über die Bewegungszeit', () {
      // 5 m/s über 119 bewegte Sekunden sind 595 m — die Ampelminute macht daraus
      // sonst rechnerisch ein langsameres Tempo, ohne dass jemand langsamer war.
      final a = parser.parse(
        csvMit([...takt(0, 59, 5), ...takt(60, 119, 0), ...takt(120, 179, 5)]),
        '2026-08-25_190100.csv',
      )!;
      expect(a.paceSecPerKm, (a.activeSec / a.distanceKm).round());
      expect(a.paceSecPerKm, lessThan((a.durationSec / a.distanceKm).round()));
    });
  });

  group('Ohne gemessene Bewegungszeit', () {
    // Einheiten, die vor dieser Version eingelesen wurden, haben keine. Sie dürfen
    // deshalb nicht plötzlich mit null Minuten dastehen.
    test('fällt auf die Gesamtzeit zurück', () {
      final a = fahrt(datum: '2026-08-25', durationSec: 3600, movingSec: 0);
      expect(a.activeSec, 3600);
      expect(a.pausedSec, 0, reason: 'Nichts gemessen heißt nicht: eine Stunde Pause');
    });

    test('überlebt den Weg durch den Zwischenspeicher', () {
      final a = fahrt(datum: '2026-08-25', durationSec: 3600, movingSec: 2400);
      final wieder = Activity.fromJson(a.toJson());
      expect(wieder.movingSec, 2400);
      expect(wieder.activeSec, 2400);
    });
  });

  group('Zwischenspeicher', () {
    // Ohne diesen Schritt behielten alle bereits eingelesenen Fahrten für immer ihre
    // Gesamtzeit: Der Abgleich überspringt sie ja anhand des Fingerabdrucks.
    test('wirft die Fingerabdrücke weg, wenn er aus einer älteren Version stammt', () {
      final alt = {
        'activities': [
          fahrt(datum: '2026-08-25', durationSec: 3600, movingSec: 0).toJson(),
        ],
        'healthDays': const [],
        'fingerprints': const {'/Fitness/a.csv': 'etag-1'},
      };

      final geladen = FitnessData.fromJson(alt);
      expect(geladen.activities, hasLength(1),
          reason: 'Die Fahrten bleiben — offline wäre der Bereich sonst leer');
      expect(geladen.fingerprints, isEmpty,
          reason: 'Damit der nächste Abgleich alles neu auswertet');
    });

    test('behält sie beim eigenen Stand', () {
      const daten = FitnessData(fingerprints: {'/Fitness/a.csv': 'etag-1'});
      expect(FitnessData.fromJson(daten.toJson()).fingerprints, hasLength(1));
    });
  });

  group('Wochenminuten', () {
    Sport rad(Activity a) => Sport.cycling;

    test('zählen nur die Zeit in Bewegung', () {
      final woche = cyclingWeeks(
        [fahrt(datum: '2026-08-25', durationSec: 3600, movingSec: 1800)],
        rad,
        DateTime(2026, 8, 27),
        weeksBack: 0,
        weeksForward: 0,
      ).single;

      expect(woche.minutes, 30, reason: 'Eine Stunde unterwegs, 30 Minuten gefahren');
    });

    test('nehmen alte Einheiten weiter mit der Gesamtzeit', () {
      final woche = cyclingWeeks(
        [fahrt(datum: '2026-08-25', durationSec: 3600, movingSec: 0)],
        rad,
        DateTime(2026, 8, 27),
        weeksBack: 0,
        weeksForward: 0,
      ).single;

      expect(woche.minutes, 60);
    });

    test('färben abgeschlossene Wochen nach der Bewegungszeit', () {
      // 130 Minuten unterwegs, davon 90 gefahren: das Ziel ist damit nicht erreicht.
      final stufen = completedWeekLevels(
        [fahrt(datum: '2026-08-18', durationSec: 130 * 60, movingSec: 90 * 60)],
        rad,
        DateTime(2026, 8, 27),
      );
      expect(stufen[DateTime(2026, 8, 17)], WeeklyLevel.zuWenig);
    });
  });
}
