import 'dart:convert';

import '../../core/auth/nextcloud_account.dart';
import 'fitness_overrides.dart';
import 'fitness_webdav.dart';

/// Datei im Datenordner, in der die Korrekturen von Hand liegen.
const String kOverridesFileName = 'korrekturen.json';

/// Ergebnis eines Abgleichs: was lokal gelten soll, und ob es neu ist.
class OverridesSyncResult {
  const OverridesSyncResult({this.uebernehmen, this.stand, this.hochgeladen = false});

  /// Nicht `null`: diesen Stand lokal übernehmen.
  final FitnessOverrides? uebernehmen;
  final DateTime? stand;
  final bool hochgeladen;
}

/// Hält die Korrekturen (Sportart, Art der Einheit, E-Motor, Zeiten) in der Nextcloud.
///
/// Sie sind das Einzige im Gesundheitsbereich, was sich nicht aus den Dateien
/// wiederherstellen lässt. Lagen sie nur auf dem Handy, waren sie bei einem
/// Gerätewechsel verloren — und ein zweites Gerät sah sie nie.
///
/// Es gilt der jüngere Stand als Ganzes. Für eine Person mit einem Hauptgerät ist das
/// richtig und einfach; eine Zusammenführung je Eintrag bräuchte Löschmarken und
/// brächte für diesen Fall nichts.
class OverridesCloud {
  OverridesCloud({WebDavClient? client}) : _client = client ?? const WebDavClient();

  final WebDavClient _client;

  static String pathOf(String folder) {
    final f = folder.endsWith('/') ? folder.substring(0, folder.length - 1) : folder;
    return '$f/$kOverridesFileName';
  }

  Future<void> upload({
    required NextcloudAccount account,
    required String folder,
    required FitnessOverrides overrides,
    required DateTime stand,
  }) async {
    const enc = JsonEncoder.withIndent(' ');
    await _client.write(
      account,
      pathOf(folder),
      enc.convert({
        'stand': stand.toUtc().toIso8601String(),
        'korrekturen': overrides.toJson(),
      }),
    );
  }

  /// [lokalStand] ist `null`, wenn auf diesem Gerät noch nie mit Zeitstempel geändert
  /// wurde — dann stammen vorhandene lokale Korrekturen aus der Zeit vor dem Abgleich
  /// und werden mit der Datei zusammengeführt statt verworfen.
  Future<OverridesSyncResult> sync({
    required NextcloudAccount account,
    required String folder,
    required FitnessOverrides lokal,
    required DateTime? lokalStand,
  }) async {
    final entfernt = await _lies(account, folder);
    if (entfernt == null) {
      if (lokal.isEmpty) return const OverridesSyncResult();
      final stand = lokalStand ?? DateTime.now();
      await upload(account: account, folder: folder, overrides: lokal, stand: stand);
      return const OverridesSyncResult(hochgeladen: true);
    }

    final (fern, fernStand) = entfernt;
    if (lokalStand == null) {
      final zusammen = mergeOverrides(vorrang: fern, rest: lokal);
      final stand = DateTime.now();
      if (!lokal.isEmpty) {
        await upload(account: account, folder: folder, overrides: zusammen, stand: stand);
      }
      return OverridesSyncResult(uebernehmen: zusammen, stand: stand, hochgeladen: !lokal.isEmpty);
    }
    if (fernStand.isAfter(lokalStand)) {
      return OverridesSyncResult(uebernehmen: fern, stand: fernStand);
    }
    if (lokalStand.isAfter(fernStand)) {
      await upload(account: account, folder: folder, overrides: lokal, stand: lokalStand);
      return const OverridesSyncResult(hochgeladen: true);
    }
    return const OverridesSyncResult();
  }

  Future<(FitnessOverrides, DateTime)?> _lies(NextcloudAccount account, String folder) async {
    final String text;
    try {
      text = await _client.read(account, pathOf(folder));
    } on WebDavException catch (e) {
      // Noch keine Datei: der Normalfall beim ersten Mal.
      if (e.message.contains('(404)')) return null;
      rethrow;
    }
    final j = jsonDecode(text) as Map<String, dynamic>;
    final stand = DateTime.tryParse(j['stand'] as String? ?? '') ?? DateTime(2000);
    return (
      FitnessOverrides.fromJson((j['korrekturen'] as Map).cast<String, dynamic>()),
      stand.toLocal(),
    );
  }
}

/// [vorrang] gewinnt bei Widerspruch; was nur in [rest] steht, kommt dazu.
FitnessOverrides mergeOverrides({
  required FitnessOverrides vorrang,
  required FitnessOverrides rest,
}) =>
    FitnessOverrides(
      sports: {...rest.sports, ...vorrang.sports},
      types: {...rest.types, ...vorrang.types},
      ebikes: {
        ...rest.ebikes.where((id) => !vorrang.notEbikes.contains(id)),
        ...vorrang.ebikes,
      },
      notEbikes: {
        ...rest.notEbikes.where((id) => !vorrang.ebikes.contains(id)),
        ...vorrang.notEbikes,
      },
      times: {...rest.times, ...vorrang.times},
      hidden: {...rest.hidden, ...vorrang.hidden},
    );
