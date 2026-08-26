import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/auth/account_providers.dart';
import 'fitness_models.dart';
import 'fitness_repository.dart';
import 'fitness_settings.dart';

final fitnessRepositoryProvider =
    Provider<FitnessRepository>((ref) => FitnessRepository());

/// Zuletzt gemeldetes Ergebnis eines Abgleichs, für die Anzeige in den Einstellungen.
final fitnessStatusProvider =
    NotifierProvider<FitnessStatusNotifier, String?>(FitnessStatusNotifier.new);

class FitnessStatusNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? value) => state = value;
}

/// Läuft gerade ein Abgleich?
final fitnessSyncingProvider =
    NotifierProvider<FitnessSyncingNotifier, bool>(FitnessSyncingNotifier.new);

class FitnessSyncingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool value) => state = value;
}

/// Die eingelesenen Trainings- und Gesundheitsdaten.
///
/// Beim Start kommt zuerst der Zwischenspeicher — die Oberfläche steht damit sofort, auch
/// ohne Netz. Der Abgleich mit der Nextcloud läuft danach im Hintergrund.
final fitnessDataProvider =
    AsyncNotifierProvider<FitnessDataController, FitnessData>(
  FitnessDataController.new,
);

class FitnessDataController extends AsyncNotifier<FitnessData> {
  bool _autoSyncDone = false;

  @override
  Future<FitnessData> build() async {
    final repo = ref.watch(fitnessRepositoryProvider);
    final cached = await repo.load();

    final enabled = await ref.watch(fitnessEnabledProvider.future);
    final folder = await ref.watch(fitnessFolderProvider.future);
    if (enabled && folder.isNotEmpty && !_autoSyncDone) {
      _autoSyncDone = true;
      // Nicht abwarten: der Bestand aus dem Zwischenspeicher reicht zum Anzeigen.
      Future.microtask(() => sync(announceNothingNew: false));
    }
    return cached;
  }

  Future<void> sync({bool force = false, bool announceNothingNew = true}) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) {
      ref.read(fitnessStatusProvider.notifier).set(
          'Keine Nextcloud eingerichtet — das geht in den Einstellungen unter Konto.');
      return;
    }
    final folder = await ref.read(fitnessFolderProvider.future);
    if (folder.isEmpty) {
      ref.read(fitnessStatusProvider.notifier).set('Noch kein Datenordner gewählt.');
      return;
    }

    ref.read(fitnessSyncingProvider.notifier).set(true);
    try {
      final repo = ref.read(fitnessRepositoryProvider);
      final previous = state.value ?? await repo.load();
      final (merged, result) = await repo.import(
        account: account,
        folder: folder,
        previous: previous,
        force: force,
      );

      state = AsyncData(merged);

      final status = switch (result) {
        ImportResult(error: final e?) => e,
        ImportResult(hasNews: true) =>
          '${result.newActivities} Einheiten, ${result.newHealthDays} Tagesdaten eingelesen.'
              '${result.unreadable > 0 ? ' ${result.unreadable} nicht lesbar.' : ''}',
        _ when announceNothingNew => 'Keine neuen Dateien gefunden.'
            '${result.unreadable > 0 ? ' ${result.unreadable} nicht lesbar.' : ''}',
        _ => null,
      };
      if (status != null) {
        ref.read(fitnessStatusProvider.notifier).set(status);
      }
    } finally {
      ref.read(fitnessSyncingProvider.notifier).set(false);
    }
  }

  Future<void> clear() async {
    await ref.read(fitnessRepositoryProvider).clear();
    state = const AsyncData(FitnessData());
    ref.read(fitnessStatusProvider.notifier).set(
        'Eingelesene Daten gelöscht. Gewicht und Ordner bleiben erhalten.');
  }
}

/// Von Hand eingetragene Gewichtswerte.
///
/// Bewusst in einer eigenen Datei und nicht im Import-Zwischenspeicher: diese Werte sind
/// das Einzige, was sich nicht aus dem Datenordner wiederherstellen lässt.
final weightEntriesProvider =
    AsyncNotifierProvider<WeightController, List<WeightEntry>>(
  WeightController.new,
);

class WeightController extends AsyncNotifier<List<WeightEntry>> {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'fitness_gewicht.json'));
  }

  Future<List<WeightEntry>> _read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return const [];
      final raw = jsonDecode(await file.readAsString()) as List;
      return raw
          .map((e) => WeightEntry.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<WeightEntry> entries) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (_) {
      // Nicht kritisch genug, um die Eingabe scheitern zu lassen.
    }
  }

  @override
  Future<List<WeightEntry>> build() => _read();

  Future<void> put(String date, double kg, {String? time}) async {
    final current = state.value ?? await _read();
    final merged = [
      ...current.where((e) => e.date != date),
      WeightEntry(date, kg, time: time),
    ]..sort((a, b) => a.date.compareTo(b.date));
    await _write(merged);
    state = AsyncData(merged);
  }

  Future<void> remove(String date) async {
    final current = state.value ?? await _read();
    final merged = current.where((e) => e.date != date).toList();
    await _write(merged);
    state = AsyncData(merged);
  }
}

/// Gewichtswerte aus Eingabe und Tagesdateien zusammengeführt.
///
/// Schreibt der Tracker ein Gewicht ins Frontmatter, wird es übernommen — ein von Hand
/// eingetippter Wert gewinnt, weil er bewusst gesetzt wurde.
final mergedWeightProvider = Provider<List<WeightEntry>>((ref) {
  final manual = ref.watch(weightEntriesProvider).value ?? const <WeightEntry>[];
  final data = ref.watch(fitnessDataProvider).value;

  final byDate = <String, WeightEntry>{};
  for (final h in data?.healthDays ?? const <HealthDay>[]) {
    final kg = h.weightKg;
    // Aus einer Tagesdatei kommt nur der Wert, keine Uhrzeit.
    if (kg != null) byDate[h.date] = WeightEntry(h.date, kg);
  }
  for (final e in manual) {
    byDate[e.date] = e;
  }

  return byDate.values.toList()..sort((a, b) => a.date.compareTo(b.date));
});
