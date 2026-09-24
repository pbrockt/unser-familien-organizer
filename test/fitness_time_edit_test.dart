import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_overrides.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Fahrt vom 24.09.2026, wie sie aus der Datei kommt: 1:27:18 gesamt, 24:27 Stand.
Activity fahrt() => Activity(
      id: 'Odernheim am Glan Rundfahrt (2).fit',
      date: '2026-09-24',
      timeOfDay: '15:11',
      sportDetected: Sport.cycling,
      sportConfidence: 1,
      durationSec: 5238,
      movingSec: 3771,
      distanceKm: 20.8,
      hrAvg: 155,
      hrMax: 186,
      hrHistogram: List<int>.filled(hrHistogramSize, 0),
      cadenceAvg: 78,
      speedAvgKmh: 19.9,
      speedMaxKmh: 47,
      speedMovingAvgKmh: 20.1,
      elevGain: 148,
      elevLoss: 152,
      series: const [],
      stoppedShare: 1467 / 5238,
    );

void main() {
  group('Zeitkorrektur von Hand', () {
    test('Fahrzeit ist Gesamtzeit minus Standzeit', () {
      final a = applyTimeEdit(fahrt(), const TimeEdit(totalSec: 5400, stoppedSec: 1800));
      expect(a.durationSec, 5400);
      expect(a.activeSec, 3600);
      expect(a.pausedSec, 1800);
      expect(a.stoppedShare, closeTo(1 / 3, 0.001));
      expect(a.timesEdited, isTrue);
    });

    test('Tempo in Bewegung folgt der neuen Fahrzeit', () {
      // 20,8 km in genau einer Stunde.
      final a = applyTimeEdit(fahrt(), const TimeEdit(totalSec: 5400, stoppedSec: 1800));
      expect(a.speedMovingAvgKmh, closeTo(20.8, 0.01));
    });

    test('ohne Standzeit ist alles Fahrzeit', () {
      final a = applyTimeEdit(fahrt(), const TimeEdit(totalSec: 3600, stoppedSec: 0));
      expect(a.activeSec, 3600);
      expect(a.pausedSec, 0);
      expect(a.stoppedShare, 0);
    });

    test('nur gestanden heißt nicht plötzlich durchgefahren', () {
      // movingSec 0 hieße im Modell „unbekannt" und fiele auf die Gesamtzeit zurück.
      final a = applyTimeEdit(fahrt(), const TimeEdit(totalSec: 600, stoppedSec: 600));
      expect(a.activeSec, lessThanOrEqualTo(1));
      expect(a.stoppedShare, 1.0);
    });

    test('Einheiten ohne Korrektur bleiben unverändert', () {
      final andere = fahrt().copyWith(id: 'andere.fit');
      final out = applyTimeEdits(
        [fahrt(), andere],
        {fahrt().id: const TimeEdit(totalSec: 5400, stoppedSec: 1800)},
      );
      expect(out[0].timesEdited, isTrue);
      expect(identical(out[1], andere), isTrue);
    });
  });

  group('Speichern', () {
    test('überlebt einen Neustart und lässt sich zurücknehmen', () async {
      SharedPreferences.setMockInitialValues({});
      final id = fahrt().id;

      var c = ProviderContainer();
      await c.read(fitnessOverridesProvider.future);
      await c
          .read(fitnessOverridesProvider.notifier)
          .setTimes(id, const TimeEdit(totalSec: 5238, stoppedSec: 1200));
      c.dispose();

      // Neuer Container = App neu gestartet.
      c = ProviderContainer();
      final geladen = await c.read(fitnessOverridesProvider.future);
      expect(geladen.times[id], const TimeEdit(totalSec: 5238, stoppedSec: 1200));

      await c.read(fitnessOverridesProvider.notifier).setTimes(id, null);
      c.dispose();

      c = ProviderContainer();
      expect((await c.read(fitnessOverridesProvider.future)).times, isEmpty);
      c.dispose();
    });

    test('andere Angaben zur Fahrt bleiben erhalten', () async {
      SharedPreferences.setMockInitialValues({});
      final id = fahrt().id;
      final c = ProviderContainer();
      await c.read(fitnessOverridesProvider.future);
      final ctrl = c.read(fitnessOverridesProvider.notifier);
      await ctrl.setEbike(id, true);
      await ctrl.setTimes(id, const TimeEdit(totalSec: 5238, stoppedSec: 1200));
      await ctrl.setSport(id, Sport.cycling);
      final o = c.read(fitnessOverridesProvider).value!;
      expect(o.ebikes, contains(id));
      expect(o.times[id], isNotNull);
      c.dispose();
    });
  });
}
