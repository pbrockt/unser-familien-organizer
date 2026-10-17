import 'dart:convert';

import 'package:family_planner/core/backup/backup_service.dart';
import 'package:family_planner/features/fitness/fitness_models.dart';
import 'package:family_planner/features/fitness/fitness_overrides.dart';
import 'package:family_planner/features/fitness/fitness_providers.dart';
import 'package:family_planner/features/fitness/fitness_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Die Sicherung geht als JSON-Datei in die Nextcloud. Geprüft wird deshalb der ganze
/// Weg — Einstellungen setzen, sichern, durch JSON, auf ein „neues Gerät"
/// zurückspielen, dort neu lesen — und nicht bloß die Map im Speicher.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Gesundheits-Einstellungen überstehen Sichern und Wiederherstellen', () async {
    SharedPreferences.setMockInitialValues({});
    var c = ProviderContainer();
    await c.read(fitnessKcalGoalProvider.notifier).set(1850);
    await c.read(fitnessWaterGoalProvider.notifier).set(2500);
    await c.read(fitnessWeeklyReportProvider.notifier).set(false);
    await c.read(fitnessStepGoalProvider.notifier).set(9000);
    await c.read(fitnessGoalWeightProvider.notifier).set(78.0);
    await c.read(fitnessOverridesProvider.future);
    final o = c.read(fitnessOverridesProvider.notifier);
    await o.setSport('a.csv', Sport.cycling);
    await o.setEbike('b.fit', false, declared: true);
    await o.setTimes('b.fit', const TimeEdit(totalSec: 5238, stoppedSec: 1467));
    await c.read(weightEntriesProvider.future);
    await c.read(weightEntriesProvider.notifier).put('2026-10-15', 81.4, time: '07:10');
    c.dispose();

    // Wie in createBackup: als JSON-Text.
    final datei = jsonEncode(await BackupService.buildBackupMap());

    // Neues Gerät: alles leer, dann die Datei zurückspielen.
    SharedPreferences.setMockInitialValues({});
    await BackupService.applyBackupMap(jsonDecode(datei) as Map<String, dynamic>);

    c = ProviderContainer();
    addTearDown(c.dispose);
    expect(await c.read(fitnessKcalGoalProvider.future), 1850);
    expect(await c.read(fitnessWaterGoalProvider.future), 2500);
    expect(await c.read(fitnessWeeklyReportProvider.future), isFalse);
    expect(await c.read(fitnessStepGoalProvider.future), 9000);
    // Kommazahl bleibt Kommazahl — 78.0 darf nicht als Ganzzahl zurückkommen.
    expect(await c.read(fitnessGoalWeightProvider.future), 78.0);
    final zurueck = await c.read(fitnessOverridesProvider.future);
    expect(zurueck.sports, {'a.csv': Sport.cycling});
    expect(zurueck.notEbikes, {'b.fit'});
    expect(zurueck.times['b.fit'], const TimeEdit(totalSec: 5238, stoppedSec: 1467));
    final gewichte = await c.read(weightEntriesProvider.future);
    expect(gewichte.single.kg, 81.4);
    expect(gewichte.single.time, '07:10');
  });

  test('der Claude-Schlüssel steht nicht in der Sicherung', () async {
    // Er liegt im geschützten Speicher, nicht in den Einstellungen. Diese Prüfung
    // schlägt an, falls ihn je jemand dorthin verlegt.
    SharedPreferences.setMockInitialValues({'claude_model': 'claude-opus-5-5'});
    final datei = jsonEncode(await BackupService.buildBackupMap());
    expect(datei, contains('claude_model'));
    expect(datei, isNot(contains('claude_api_key')));
    expect(datei, isNot(contains('sk-ant')));
  });
}
