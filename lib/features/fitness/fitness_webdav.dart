import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../core/auth/nextcloud_account.dart';

/// Eine Datei oder ein Ordner im WebDAV-Baum.
class RemoteEntry {
  const RemoteEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    this.etag,
    this.size,
  });

  /// Pfad relativ zur WebDAV-Wurzel des Nutzers, beginnend mit `/`.
  final String path;
  final String name;
  final bool isDirectory;

  /// Wechselt, sobald sich der Inhalt ändert — daran hängt der inkrementelle Abgleich.
  final String? etag;
  final int? size;
}

class WebDavException implements Exception {
  WebDavException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Minimaler WebDAV-Zugriff auf die Dateien der Nextcloud.
///
/// Bewusst schlank gehalten: gebraucht werden nur „Ordner auflisten" und „Datei lesen".
/// Für CalDAV gibt es bereits einen eigenen, ausgereifteren Client — der spricht aber
/// einen anderen Endpunkt und ist hier nicht wiederverwendbar.
class WebDavClient {
  const WebDavClient({this.httpClient});

  final http.Client? httpClient;

  http.Client get _client => httpClient ?? http.Client();

  static const _propfindBody = '''<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:resourcetype/>
    <d:getetag/>
    <d:getcontentlength/>
  </d:prop>
</d:propfind>''';

  /// Listet den Inhalt eines Ordners. [folder] ist relativ zur WebDAV-Wurzel.
  Future<List<RemoteEntry>> list(
    NextcloudAccount account,
    String folder,
  ) async {
    final base = _base(account);
    final uri = Uri.parse('$base${_encodePath(folder)}');

    final request = http.Request('PROPFIND', uri)
      ..headers['Authorization'] = _auth(account)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = _propfindBody;

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);

    // 207 Multi-Status ist der Erfolgsfall für PROPFIND.
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw WebDavException(
        'Die Nextcloud hat den Zugriff abgelehnt. Stimmen Benutzername und App-Passwort?',
      );
    }
    if (response.statusCode == 404) {
      throw WebDavException('Der Ordner „$folder" existiert nicht.');
    }
    if (response.statusCode != 207) {
      throw WebDavException('Unerwartete Antwort der Nextcloud (${response.statusCode}).');
    }

    return _parseMultistatus(utf8.decode(response.bodyBytes), base, folder);
  }

  /// Lädt nur den Anfang einer Datei.
  ///
  /// Für Begleitdateien, aus denen bloß eine Kopfzeile gebraucht wird: die TCX einer
  /// Fahrt ist 775 KB groß, die enthaltene Sportart steht in den ersten paar hundert
  /// Bytes. Ohne Bereichsanfrage würde jede Fahrt ein Megabyte Datenvolumen kosten,
  /// um ein einziges Wort zu lesen.
  ///
  /// Server, die keine Bereichsanfragen beherrschen, antworten mit 200 und der ganzen
  /// Datei — dann wird eben abgeschnitten.
  Future<String> readHead(
    NextcloudAccount account,
    String path, {
    int bytes = 4096,
  }) async {
    final uri = Uri.parse('${_base(account)}${_encodePath(path)}');
    final response = await _client.get(uri, headers: {
      'Authorization': _auth(account),
      'Range': 'bytes=0-${bytes - 1}',
    });
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw WebDavException(
        'Datei „$path" konnte nicht gelesen werden (${response.statusCode}).',
      );
    }
    final roh = response.bodyBytes.length > bytes
        ? response.bodyBytes.sublist(0, bytes)
        : response.bodyBytes;
    // allowMalformed: ein Schnitt mitten durch ein Mehrbyte-Zeichen darf nicht werfen.
    return utf8.decode(roh, allowMalformed: true);
  }

  /// Lädt eine Datei als Text.
  Future<String> read(NextcloudAccount account, String path) async {
    final uri = Uri.parse('${_base(account)}${_encodePath(path)}');
    final response = await _client.get(uri, headers: {
      'Authorization': _auth(account),
    });
    if (response.statusCode != 200) {
      throw WebDavException(
        'Datei „$path" konnte nicht gelesen werden (${response.statusCode}).',
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  String _base(NextcloudAccount account) {
    final b = account.webdavBase;
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  String _auth(NextcloudAccount account) =>
      'Basic ${base64Encode(utf8.encode(account.credentials))}';

  /// Kodiert je Pfadsegment. Ein Ordner „Meine Daten" muss als `Meine%20Daten` gehen,
  /// die Schrägstriche selbst dürfen dabei nicht mitkodiert werden.
  String _encodePath(String path) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    if (clean.isEmpty) return '/';
    final encoded =
        clean.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    return '/$encoded';
  }

  List<RemoteEntry> _parseMultistatus(String body, String base, String folder) {
    final doc = XmlDocument.parse(body);
    final basePath = Uri.parse(base).path;
    final out = <RemoteEntry>[];

    // Namensraum-Präfixe unterscheiden sich je nach Server (d:, D:, lp1:) — deshalb
    // wird über den lokalen Namen gesucht statt über den Präfix.
    for (final response in doc.findAllElements('response', namespaceUri: '*')) {
      final href = response.getElement('href', namespaceUri: '*')?.innerText;
      if (href == null) continue;

      var path = Uri.decodeComponent(Uri.parse(href).path);
      if (path.startsWith(basePath)) path = path.substring(basePath.length);
      if (!path.startsWith('/')) path = '/$path';

      final isDir = response.findAllElements('collection', namespaceUri: '*').isNotEmpty;
      final normalized = isDir && path.endsWith('/') && path.length > 1
          ? path.substring(0, path.length - 1)
          : path;

      // Der angefragte Ordner selbst steht mit in der Antwort und wird übersprungen.
      final requested = folder.endsWith('/') && folder.length > 1
          ? folder.substring(0, folder.length - 1)
          : folder;
      if (normalized == requested || normalized.isEmpty || normalized == '/') continue;

      final name = normalized.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
      final etag = response
          .findAllElements('getetag', namespaceUri: '*')
          .firstOrNull
          ?.innerText
          .replaceAll('"', '');
      final sizeText = response
          .findAllElements('getcontentlength', namespaceUri: '*')
          .firstOrNull
          ?.innerText;

      out.add(RemoteEntry(
        path: normalized,
        name: name,
        isDirectory: isDir,
        etag: etag == null || etag.isEmpty ? null : etag,
        size: sizeText == null ? null : int.tryParse(sizeText),
      ));
    }

    out.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }
}
