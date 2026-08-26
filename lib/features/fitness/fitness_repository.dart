import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/auth/nextcloud_account.dart';
import 'fitness_models.dart';
import 'fitness_parsers.dart';
import 'fitness_sport_hint.dart';
import 'fitness_webdav.dart';

/// Zusammengefasster Stand aller eingelesenen Dateien.
class FitnessData {
  const FitnessData({
    this.activities = const [],
    this.healthDays = const [],
    this.fingerprints = const {},
  });

  final List<Activity> activities;
  final List<HealthDay> healthDays;

  /// Datei-Fingerabdrücke (Pfad → ETag bzw. Größe), damit Unverändertes nicht erneut
  /// geladen und geparst wird.
  final Map<String, String> fingerprints;

  Map<String, dynamic> toJson() => {
        'activities': activities.map((a) => a.toJson()).toList(),
        'healthDays': healthDays.map((h) => h.toJson()).toList(),
        'fingerprints': fingerprints,
      };

  factory FitnessData.fromJson(Map<String, dynamic> j) => FitnessData(
        activities: (j['activities'] as List?)
                ?.map((e) => Activity.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        healthDays: (j['healthDays'] as List?)
                ?.map((e) => HealthDay.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        fingerprints: (j['fingerprints'] as Map?)?.map(
              (k, v) => MapEntry(k as String, v as String),
            ) ??
            const {},
      );
}

class ImportResult {
  const ImportResult({
    this.newActivities = 0,
    this.newHealthDays = 0,
    this.skippedUnchanged = 0,
    this.unreadable = 0,
    this.error,
  });

  final int newActivities;
  final int newHealthDays;
  final int skippedUnchanged;
  final int unreadable;
  final String? error;

  bool get hasNews => newActivities > 0 || newHealthDays > 0;
}

/// Liest den eingestellten Nextcloud-Ordner und hält das Ergebnis lokal vor.
///
/// Bereits gelesene Dateien werden anhand ihres ETags übersprungen. Das ist hier nicht
/// bloß Feinschliff: die Trainings-CSVs sind sekundengenaue Telemetrie, und den ganzen
/// Ordner jeden Morgen erneut zu laden wäre Verschwendung von Datenvolumen und Zeit.
class FitnessRepository {
  FitnessRepository({WebDavClient? client, this.parser = const CsvParser()})
      : _client = client ?? const WebDavClient();

  final WebDavClient _client;
  final CsvParser parser;
  static const _health = HealthParser();

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'fitness_import.json'));
  }

  Future<FitnessData> load() async {
    try {
      final file = await _cacheFile();
      if (!file.existsSync()) return const FitnessData();
      return FitnessData.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return const FitnessData();
    }
  }

  Future<void> _save(FitnessData data) async {
    try {
      final file = await _cacheFile();
      await file.writeAsString(jsonEncode(data.toJson()));
    } catch (_) {
      // Der Zwischenspeicher ist entbehrlich — beim nächsten Start wird neu gelesen.
    }
  }

  Future<void> clear() async {
    try {
      final file = await _cacheFile();
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Nichts zu tun.
    }
  }

  /// Liest den Ordner ein und mischt das Ergebnis in den vorhandenen Bestand.
  Future<(FitnessData, ImportResult)> import({
    required NextcloudAccount account,
    required String folder,
    required FitnessData previous,
    bool force = false,
  }) async {
    List<RemoteEntry> entries;
    try {
      entries = await _collect(account, folder, 0);
    } on WebDavException catch (e) {
      return (previous, ImportResult(error: e.message));
    } catch (e) {
      return (previous, ImportResult(error: 'Keine Verbindung zur Nextcloud: $e'));
    }

    // Begleitdateien nach Namen greifbar machen (`2026-08-25_190102.tcx`).
    final nachName = {for (final e in entries) e.name.toLowerCase(): e};

    final activities = {for (final a in previous.activities) a.id: a};
    final healthDays = {for (final h in previous.healthDays) h.date: h};
    final fingerprints = Map<String, String>.from(previous.fingerprints);

    var newActivities = 0, newHealth = 0, skipped = 0, unreadable = 0;

    for (final entry in entries) {
      final lower = entry.name.toLowerCase();
      final isCsv = lower.endsWith('.csv');
      final isMd = lower.endsWith('.md');
      if (!isCsv && !isMd) continue;

      // Ohne ETag hilft die Größe — besser als jedes Mal neu zu laden.
      final fingerprint = entry.etag ?? 'size:${entry.size}';
      if (!force && fingerprints[entry.path] == fingerprint) {
        skipped++;
        continue;
      }

      String text;
      try {
        text = await _client.read(account, entry.path);
      } catch (_) {
        unreadable++;
        continue;
      }

      if (isCsv) {
        var parsed = parser.parse(text, entry.name);
        if (parsed != null) {
          final erklaert = await _declaredSport(account, entry.name, nachName);
          if (erklaert != null) parsed = parsed.copyWith(sportDeclared: erklaert);
          activities[parsed.id] = parsed;
          fingerprints[entry.path] = fingerprint;
          newActivities++;
        } else {
          unreadable++;
        }
      } else {
        final parsed = _health.parse(text, entry.name);
        if (parsed != null) {
          healthDays[parsed.date] = parsed;
          fingerprints[entry.path] = fingerprint;
          newHealth++;
        } else {
          unreadable++;
        }
      }
    }

    final merged = FitnessData(
      activities: activities.values.toList()
        ..sort((a, b) => (a.date + a.timeOfDay).compareTo(b.date + b.timeOfDay)),
      healthDays: healthDays.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
      fingerprints: fingerprints,
    );
    await _save(merged);

    return (
      merged,
      ImportResult(
        newActivities: newActivities,
        newHealthDays: newHealth,
        skippedUnchanged: skipped,
        unreadable: unreadable,
      )
    );
  }

  /// Fragt die Sportart aus einer Begleitdatei ab, falls es eine gibt.
  ///
  /// Gelesen werden nur die ersten Kilobytes — die Angabe steht im Kopf. Schlägt das
  /// fehl, ist das kein Fehler der Einheit: dann greift wieder die Schätzung.
  Future<Sport?> _declaredSport(
    NextcloudAccount account,
    String csvName,
    Map<String, RemoteEntry> nachName,
  ) async {
    for (final name in SportHint.companionNames(csvName)) {
      final datei = nachName[name.toLowerCase()];
      if (datei == null) continue;
      try {
        final kopf = await _client.readHead(account, datei.path);
        final sport = SportHint.parse(kopf);
        if (sport != null) return sport;
      } catch (_) {
        // Weiter zur nächsten Begleitdatei.
      }
    }
    return null;
  }

  /// Sammelt Dateien rekursiv, aber flach genug, dass ein tief verschachtelter Baum
  /// nicht bremst.
  Future<List<RemoteEntry>> _collect(
    NextcloudAccount account,
    String folder,
    int depth,
  ) async {
    if (depth > 3) return const [];
    final entries = await _client.list(account, folder);
    final out = <RemoteEntry>[];
    for (final e in entries) {
      if (e.isDirectory) {
        out.addAll(await _collect(account, e.path, depth + 1));
      } else {
        out.add(e);
      }
    }
    return out;
  }
}
