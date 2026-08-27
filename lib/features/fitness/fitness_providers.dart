import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/account_providers.dart';
import 'fitness_models.dart';
import 'fitness_overrides.dart';
import 'fitness_streak.dart';
import 'fitness_weekly.dart';
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

/// Liest die gespeicherte Gewichtsliste. Kaputte oder fremde Inhalte ergeben eine leere
/// Liste statt eines Absturzes — eine unlesbare Sicherung darf die App nicht lahmlegen.
List<WeightEntry> decodeWeightEntries(String raw) {
  try {
    final liste = jsonDecode(raw);
    if (liste is! List) return const [];
    final out = <WeightEntry>[];
    for (final e in liste) {
      if (e is Map<String, dynamic> && e['date'] is String && e['kg'] is num) {
        out.add(WeightEntry.fromJson(e));
      }
    }
    out.sort((a, b) => a.date.compareTo(b.date));
    return out;
  } catch (_) {
    return const [];
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
  /// Schlüssel in den Einstellungen.
  ///
  /// Die Gewichte liegen bewusst **dort** und nicht in einer eigenen Datei: die
  /// Nextcloud-Sicherung überträgt die Einstellungen, und die Gewichtswerte sind das
  /// Einzige in der App, was sich nicht aus dem Datenordner wiederherstellen lässt.
  /// In einer separaten Datei wären sie beim Gerätewechsel verloren gewesen.
  /// Der Platzbedarf ist unkritisch — ein Eintrag je Tag sind rund 15 KB im Jahr.
  static const prefsKey = 'fitness_weight_entries';

  /// Frühere Ablage; wird beim ersten Start einmalig übernommen.
  Future<File> _legacyFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'fitness_gewicht.json'));
  }

  Future<List<WeightEntry>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);

    if (raw != null) return decodeWeightEntries(raw);

    // Noch nichts in den Einstellungen: alte Datei übernehmen und danach dort führen.
    final ausDatei = await _readLegacy();
    if (ausDatei.isNotEmpty) await _write(ausDatei);
    return ausDatei;
  }

  Future<List<WeightEntry>> _readLegacy() async {
    try {
      final file = await _legacyFile();
      if (!file.existsSync()) return const [];
      return decodeWeightEntries(await file.readAsString());
    } catch (_) {
      return const [];
    }
  }

  Future<void> _write(List<WeightEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
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

/// Die Serie erreichter Schritteziele.
///
/// Liefert bei abgeschaltetem Fitness-Bereich eine leere Serie — Startseite und Kalender
/// fragen den Provider bedingungslos ab und sollen dann schlicht nichts anzeigen.
final stepStreakProvider = Provider<StepStreak>((ref) {
  final enabled = ref.watch(fitnessEnabledProvider).value ?? false;
  if (!enabled) return StepStreak.leer;

  final data = ref.watch(fitnessDataProvider).value;
  if (data == null || data.healthDays.isEmpty) return StepStreak.leer;

  final goal = ref.watch(fitnessStepGoalProvider).value ?? 8000;
  return computeStepStreak(data.healthDays, goal, DateTime.now());
});

/// Bewertung je abgeschlossener Radwoche, abgelegt nach dem Montag der Woche.
///
/// Für die Einfärbung der Kalenderwochen. Nur abgeschlossene Wochen: die laufende ist
/// noch nicht entschieden, eine künftige erst recht nicht.
final completedWeekLevelsProvider = Provider<Map<DateTime, WeeklyLevel>>((ref) {
  final enabled = ref.watch(fitnessEnabledProvider).value ?? false;
  if (!enabled) return const {};

  final data = ref.watch(fitnessDataProvider).value;
  if (data == null || data.activities.isEmpty) return const {};

  final overrides = ref.watch(fitnessOverridesProvider).value;
  Sport sportOf(Activity a) => overrides?.sports[a.id] ?? a.sportEffective;

  return completedWeekLevels(data.activities, sportOf, DateTime.now());
});

/// Alle Tage mit erreichtem Schritteziel — für die Markierung im Kalender.
final stepGoalDatesProvider = Provider<Set<String>>(
  (ref) => ref.watch(stepStreakProvider).reachedDates,
);

/// Schritte des heutigen Tages, sofern schon eingelesen.
final todayStepsProvider = Provider<int?>((ref) {
  final data = ref.watch(fitnessDataProvider).value;
  if (data == null) return null;
  final now = DateTime.now();
  final heute = '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  for (final d in data.healthDays) {
    if (d.date == heute) return d.steps;
  }
  return null;
});

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
