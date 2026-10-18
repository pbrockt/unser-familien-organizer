import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/nextcloud_account.dart';
import 'fitness_models.dart';
import 'fitness_webdav.dart';
import 'health_connect_file.dart';
import 'health_connect_mapping.dart';
import 'health_connect_track.dart';
import 'health_connect_source.dart';

/// Was ein Abgleich mit Health Connect bewirkt hat.
class HcSyncResult {
  const HcSyncResult({
    this.tage = 0,
    this.geschrieben = 0,
    this.unveraendert = 0,
    this.geschuetzt = 0,
    this.fehler,
  });

  /// Tage mit Daten aus Health Connect.
  final int tage;
  final int geschrieben;
  final int unveraendert;

  /// Von Hand geänderte Tage, die deshalb stehen blieben.
  final int geschuetzt;
  final String? fehler;

  HcSyncResult operator +(HcSyncResult o) => HcSyncResult(
        tage: tage + o.tage,
        geschrieben: geschrieben + o.geschrieben,
        unveraendert: unveraendert + o.unveraendert,
        geschuetzt: geschuetzt + o.geschuetzt,
        fehler: fehler ?? o.fehler,
      );

  String get text {
    if (fehler != null) return fehler!;
    final teile = [
      '$tage Tage gelesen',
      if (geschrieben > 0) '$geschrieben gespeichert',
      if (geschuetzt > 0) '$geschuetzt von Hand geändert, nicht überschrieben',
    ];
    return teile.join(' · ');
  }
}

/// Holt Tageswerte aus Health Connect und legt sie als `.md` in der Nextcloud ab.
///
/// Die Nextcloud ist dabei die eigentliche Ablage: Was dort liegt, liest der normale
/// Import wie jede andere Tagesdatei. Die App merkt sich nichts Eigenes — so kommen
/// dieselben Daten auch auf einem zweiten Gerät oder nach einer Neuinstallation an.
class HealthConnectSync {
  HealthConnectSync({HealthConnectSource? quelle, WebDavClient? client})
      : _quelle = quelle ?? HealthConnectSource(),
        _client = client ?? const WebDavClient();

  final HealthConnectSource _quelle;
  final WebDavClient _client;

  static const enabledKey = 'fitness_hc_enabled';
  static const _lastRunKey = 'fitness_hc_last_run';
  static const statusKey = 'fitness_hc_status';

  /// Gewählte Quelle der Schritte; fehlt der Eintrag, gilt die Summe von Health Connect.
  static const stepsSourceKey = 'fitness_steps_source';

  /// Schritte je App von heute, als JSON — für die Auswahl in den Einstellungen.
  static const stepsTodayKey = 'fitness_steps_by_source_today';

  static Future<String?> stepsSource() async =>
      (await SharedPreferences.getInstance()).getString(stepsSourceKey);

  static Future<void> setStepsSource(String? quelle) async {
    final prefs = await SharedPreferences.getInstance();
    if (quelle == null) {
      await prefs.remove(stepsSourceKey);
    } else {
      await prefs.setString(stepsSourceKey, quelle);
    }
  }

  /// Datum und Schritte je App vom letzten Abruf.
  static Future<(String, Map<String, int>)?> stepsToday() async {
    final roh = (await SharedPreferences.getInstance()).getString(stepsTodayKey);
    if (roh == null) return null;
    try {
      final j = jsonDecode(roh) as Map<String, dynamic>;
      return (
        j['date'] as String,
        (j['sources'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
      );
    } catch (_) {
      return null;
    }
  }

  /// Abstand zwischen zwei Abrufen. Etwas unter 30 Minuten, weil der Hintergrund-Job
  /// alle 15 Minuten läuft und Android ihn gern ein paar Sekunden früher startet.
  static const abstand = Duration(minutes: 29);

  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(enabledKey) ?? false;

  static Future<void> setEnabled(bool an) async =>
      (await SharedPreferences.getInstance()).setBool(enabledKey, an);

  /// Holt die letzten Tage, sofern eingeschaltet und der letzte Abruf lange genug her
  /// ist. Für den Hintergrund-Job und den Start der App.
  Future<HcSyncResult?> runIfDue({
    required NextcloudAccount account,
    required String fitnessFolder,
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(enabledKey) ?? false) || fitnessFolder.isEmpty) return null;
    final zuletzt = prefs.getInt(_lastRunKey);
    final jetzt = DateTime.now();
    if (!force &&
        zuletzt != null &&
        jetzt.difference(DateTime.fromMillisecondsSinceEpoch(zuletzt)) < abstand) {
      return null;
    }
    if (await _quelle.status() != HcStatus.bereit) return null;

    // Heute und zwei Tage zurück: Schlaf und Werte, die das Band erst später
    // überträgt, kommen so noch nach.
    final von = DateTime(jetzt.year, jetzt.month, jetzt.day - 2);
    final r = await _zeitraum(account, fitnessFolder, von, jetzt);
    await prefs.setInt(_lastRunKey, jetzt.millisecondsSinceEpoch);
    await prefs.setString(statusKey, '${_uhrzeit(jetzt)}: ${r.text}');
    return r;
  }

  /// Ersteinrichtung: alles, was Health Connect herausgibt, in Blöcken von 30 Tagen
  /// rückwärts — bis drei Blöcke hintereinander leer bleiben.
  Future<HcSyncResult> runFullHistory({
    required NextcloudAccount account,
    required String fitnessFolder,
    void Function(String)? fortschritt,
  }) async {
    final jetzt = DateTime.now();
    var ende = jetzt;
    var leer = 0;
    var summe = const HcSyncResult();
    // Höchstens zehn Jahre — eine Grenze für den Fall, dass immer etwas kommt.
    for (var block = 0; block < 122 && leer < 3; block++) {
      final von = DateTime(ende.year, ende.month, ende.day - 30);
      fortschritt?.call('Lese ${dayKey(von)} bis ${dayKey(ende)} …');
      final r = await _zeitraum(account, fitnessFolder, von, ende);
      summe = summe + r;
      if (r.fehler != null) break;
      leer = r.tage == 0 ? leer + 1 : 0;
      ende = von;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastRunKey, jetzt.millisecondsSinceEpoch);
    await prefs.setString(statusKey, '${_uhrzeit(jetzt)}: ${summe.text}');
    return summe;
  }

  Future<HcSyncResult> _zeitraum(
    NextcloudAccount account,
    String fitnessFolder,
    DateTime von,
    DateTime bis,
  ) async {
    final List<HealthDay> tage;
    final trainingsJeTag = <String, List<HcTraining>>{};
    // Fahrten mit Verlauf: Dateiname → CSV.
    final fahrten = <String, String>{};
    try {
      // Einen Tag früher anfragen: Eine Nacht, die um 23 Uhr beginnt, gehört zum
      // ersten Tag des Zeitraums, beginnt aber davor.
      final abruf = await _quelle.abrufen(
        von: DateTime(von.year, von.month, von.day - 1),
        bis: bis,
      );
      final ersterTag = dayKey(von);
      final prefs = await SharedPreferences.getInstance();
      final heute = dayKey(DateTime.now());
      final heuteJeQuelle = stepsBySource(abruf.samples, heute);
      if (heuteJeQuelle.isNotEmpty) {
        await prefs.setString(
          stepsTodayKey,
          jsonEncode({'date': heute, 'sources': heuteJeQuelle}),
        );
      }
      // Endet der Zeitraum um Mitternacht, gehört dieser Tag schon zum nächsten Block.
      final letzterTag = dayKey(bis.subtract(const Duration(seconds: 1)));
      tage = healthDaysFromHc(
        samples: abruf.samples,
        workouts: abruf.workouts,
        stepsPerDay: abruf.stepsPerDay,
        stepsSource: prefs.getString(stepsSourceKey),
      )
          .where((t) =>
              t.date.compareTo(ersterTag) >= 0 && t.date.compareTo(letzterTag) <= 0)
          .toList();
      final jetzt = DateTime.now();
      for (final t in trainingsFromHc(workouts: abruf.workouts, samples: abruf.samples)) {
        trainingsJeTag.putIfAbsent(dayKey(t.from), () => []).add(t);
        // Nur abgeschlossene Einheiten: Eine laufende Fahrt ergäbe einen halben Verlauf,
        // der danach nicht mehr ersetzt würde.
        if (t.to.isAfter(jetzt.subtract(const Duration(minutes: 5)))) continue;
        if (dayKey(t.from).compareTo(ersterTag) < 0) continue;
        final csv = trainingTrackCsv(
          training: t,
          samples: abruf.samples,
          routes: abruf.routes,
        );
        if (csv != null) fahrten[trainingTrackFileName(t)] = csv;
      }
    } catch (e) {
      return HcSyncResult(fehler: 'Health Connect nicht lesbar: $e');
    }
    if (tage.isEmpty) return const HcSyncResult();

    final ordner = '${_ohneSchraegstrich(fitnessFolder)}/$kHcFolderName';
    try {
      await _client.ensureFolder(account, ordner);
      if (fahrten.isNotEmpty) {
        // Eine Fahrt ändert sich nicht mehr; vorhandene Dateien bleiben, auch von Hand
        // geänderte.
        final fahrtOrdner = '$ordner/$kHcTrackFolderName';
        await _client.ensureFolder(account, fahrtOrdner);
        final da = {for (final e in await _client.list(account, fahrtOrdner)) e.name};
        for (final f in fahrten.entries) {
          if (!da.contains(f.key)) {
            await _client.write(account, '$fahrtOrdner/${f.key}', f.value);
          }
        }
      }
      final vorhanden = {
        for (final e in await _client.list(account, ordner)) e.name: e,
      };
      var geschrieben = 0, unveraendert = 0, geschuetzt = 0;
      final stand = DateTime.now();
      for (final tag in tage) {
        final name = '${tag.date}.md';
        if (vorhanden.containsKey(name)) {
          final alt = await _client.read(account, '$ordner/$name');
          if (!isUntouchedHcFile(alt)) {
            geschuetzt++;
            continue;
          }
          if (sameMeasuredValues(alt, tag, trainings: trainingsJeTag[tag.date] ?? const [])) {
            unveraendert++;
            continue;
          }
        }
        await _client.write(
          account,
          '$ordner/$name',
          healthDayToMarkdown(
            tag,
            stand: stand,
            trainings: trainingsJeTag[tag.date] ?? const [],
          ),
        );
        geschrieben++;
      }
      return HcSyncResult(
        tage: tage.length,
        geschrieben: geschrieben,
        unveraendert: unveraendert,
        geschuetzt: geschuetzt,
      );
    } on WebDavException catch (e) {
      return HcSyncResult(tage: tage.length, fehler: e.message);
    } catch (e) {
      return HcSyncResult(tage: tage.length, fehler: 'Keine Verbindung zur Nextcloud: $e');
    }
  }

  static String _ohneSchraegstrich(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  static String _uhrzeit(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
