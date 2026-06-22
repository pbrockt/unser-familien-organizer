import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../auth/nextcloud_account.dart';

/// Eine Sicherungsdatei auf der Nextcloud.
class BackupFile {
  const BackupFile({required this.href, required this.name, this.modified});
  final String href; // server-relativer Pfad (für GET/DELETE)
  final String name;
  final DateTime? modified;
}

/// Sichert App-Einstellungen & Vorlagen als JSON auf die Nextcloud (WebDAV)
/// und stellt sie wieder her. CalDAV-Daten (Termine/Aufgaben) liegen ohnehin
/// auf dem Server; Zugangsdaten werden NICHT mitgesichert.
class BackupService {
  const BackupService(this.account);
  final NextcloudAccount account;

  static const _folder = 'FamilyPlanner/Backups';

  // ---- Prefs (de)serialisieren – pur, ohne Netzwerk (unit-testbar) ----

  /// Baut die Sicherung aus allen SharedPreferences-Werten.
  static Future<Map<String, dynamic>> buildBackupMap() async {
    final prefs = await SharedPreferences.getInstance();
    final data = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      data[key] = prefs.get(key);
    }
    return {
      'app': 'family_planner',
      'type': 'settings-backup',
      'createdAt': DateTime.now().toIso8601String(),
      'prefs': data,
    };
  }

  /// Schreibt eine Sicherung zurück in die SharedPreferences.
  static Future<void> applyBackupMap(Map<String, dynamic> backup) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = backup['prefs'];
    if (raw is! Map) return;
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final v = entry.value;
      if (v is bool) {
        await prefs.setBool(key, v);
      } else if (v is int) {
        await prefs.setInt(key, v);
      } else if (v is double) {
        await prefs.setDouble(key, v);
      } else if (v is String) {
        await prefs.setString(key, v);
      } else if (v is List) {
        await prefs.setStringList(key, v.map((e) => e.toString()).toList());
      }
    }
  }

  // ---- WebDAV ----

  http.Client _client() {
    if (!account.allowInsecureCert) return http.Client();
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(inner);
  }

  Map<String, String> get _auth => {
    'Authorization': 'Basic ${base64Encode(utf8.encode(account.credentials))}',
  };

  String _fileUrl(String name) => '${account.webdavBase}$_folder/$name';

  String _absolute(String href) =>
      href.startsWith('http') ? href : '${account.baseUrl}$href';

  Future<void> _mkcol(http.Client client, String url) async {
    final req = http.Request('MKCOL', Uri.parse(url))..headers.addAll(_auth);
    final res = await http.Response.fromStream(await client.send(req));
    // 201 = angelegt, 405 = existiert bereits → beides ok.
    if (res.statusCode != 201 && res.statusCode != 405) {
      throw Exception('MKCOL $url fehlgeschlagen: ${res.statusCode}');
    }
  }

  Future<void> _ensureFolders(http.Client client) async {
    await _mkcol(client, '${account.webdavBase}FamilyPlanner');
    await _mkcol(client, '${account.webdavBase}$_folder');
  }

  /// Erstellt eine neue Sicherung und gibt den Dateinamen zurück.
  Future<String> createBackup() async {
    final client = _client();
    try {
      await _ensureFolders(client);
      final body = jsonEncode(await buildBackupMap());
      final name = 'backup-${_stamp(DateTime.now())}.json';
      final res = await client.put(
        Uri.parse(_fileUrl(name)),
        headers: {..._auth, 'content-type': 'application/json'},
        body: utf8.encode(body),
      );
      if (res.statusCode != 201 && res.statusCode != 204) {
        throw Exception('Sichern fehlgeschlagen: ${res.statusCode}');
      }
      return name;
    } finally {
      client.close();
    }
  }

  /// Listet vorhandene Sicherungen (neueste zuerst).
  Future<List<BackupFile>> listBackups() async {
    final client = _client();
    try {
      final req = http.Request(
        'PROPFIND',
        Uri.parse('${account.webdavBase}$_folder'),
      )..headers.addAll({..._auth, 'Depth': '1'});
      final res = await http.Response.fromStream(await client.send(req));
      if (res.statusCode == 404) return [];
      if (res.statusCode != 207) {
        throw Exception('Liste fehlgeschlagen: ${res.statusCode}');
      }
      final doc = XmlDocument.parse(res.body);
      final out = <BackupFile>[];
      for (final r in doc.findAllElements('response', namespaceUri: '*')) {
        final href = r.getElement('href', namespaceUri: '*')?.innerText ?? '';
        if (!href.toLowerCase().endsWith('.json')) continue;
        final name = Uri.decodeComponent(href.split('/').last);
        final mods = r
            .findAllElements('getlastmodified', namespaceUri: '*')
            .map((e) => e.innerText)
            .toList();
        DateTime? mod;
        if (mods.isNotEmpty) {
          try {
            mod = HttpDate.parse(mods.first);
          } catch (_) {}
        }
        out.add(BackupFile(href: href, name: name, modified: mod));
      }
      out.sort((a, b) => b.name.compareTo(a.name));
      return out;
    } finally {
      client.close();
    }
  }

  /// Lädt den Inhalt einer Sicherung.
  Future<Map<String, dynamic>> download(BackupFile file) async {
    final client = _client();
    try {
      final res = await client.get(
        Uri.parse(_absolute(file.href)),
        headers: _auth,
      );
      if (res.statusCode != 200) {
        throw Exception('Laden fehlgeschlagen: ${res.statusCode}');
      }
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Future<void> delete(BackupFile file) async {
    final client = _client();
    try {
      await client.delete(Uri.parse(_absolute(file.href)), headers: _auth);
    } finally {
      client.close();
    }
  }

  /// Behält nur die [keep] neuesten Sicherungen (für die Auto-Sicherung).
  Future<void> pruneOld({int keep = 14}) async {
    final files = await listBackups();
    if (files.length <= keep) return;
    for (final f in files.skip(keep)) {
      try {
        await delete(f);
      } catch (_) {}
    }
  }

  static String _stamp(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}${two(d.month)}${two(d.day)}-'
        '${two(d.hour)}${two(d.minute)}${two(d.second)}';
  }
}
