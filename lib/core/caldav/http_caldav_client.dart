import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:xml/xml.dart';

import '../auth/nextcloud_account.dart';
import 'caldav_client.dart';
import 'caldav_exception.dart';

/// CalDAV-Client gegen Nextcloud über HTTP (RFC 4791).
///
/// Nutzt Basic-Auth mit dem App-Passwort und unterstützt optional
/// selbst-signierte Zertifikate ([NextcloudAccount.allowInsecureCert]).
class HttpCalDavClient implements CalDavClient {
  const HttpCalDavClient();

  /// Erzeugt einen HTTP-Client; erlaubt bei Bedarf selbst-signierte Zerts.
  http.Client _clientFor(NextcloudAccount account) {
    if (!account.allowInsecureCert) return http.Client();
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(inner);
  }

  Map<String, String> _authHeaders(NextcloudAccount account) {
    final token = base64Encode(utf8.encode(account.credentials));
    return {'Authorization': 'Basic $token'};
  }

  /// Absolute URL zu einem (evtl. relativen) DAV-href bauen.
  Uri _resolve(NextcloudAccount account, String href) {
    if (href.startsWith('http')) return Uri.parse(href);
    return Uri.parse('${account.baseUrl}$href');
  }

  @override
  Future<List<CalDavCollection>> listCollections(
      NextcloudAccount account) async {
    final client = _clientFor(account);
    try {
      final request = http.Request('PROPFIND', Uri.parse(account.calendarHome))
        ..headers.addAll({
          ..._authHeaders(account),
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        })
        ..body = _propfindCollectionsBody;

      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);

      // 207 Multi-Status ist der Erfolgsfall für PROPFIND.
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw CalDavException.fromStatus(response.statusCode);
      }
      return _parseCollections(response.body);
    } on SocketException catch (e) {
      throw CalDavException('Keine Verbindung zum Server: ${e.message}');
    } on HttpException catch (e) {
      throw CalDavException('Netzwerkfehler: ${e.message}');
    } on HandshakeException {
      throw const CalDavException(
        'TLS-Zertifikat nicht vertrauenswürdig. Bei einem Heimserver mit '
        'selbst-signiertem Zertifikat die Option "Unsicheres Zertifikat '
        'erlauben" aktivieren.',
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<String?> fetchCTag(
      NextcloudAccount account, String collectionHref) async {
    final client = _clientFor(account);
    try {
      final request = http.Request('PROPFIND', _resolve(account, collectionHref))
        ..headers.addAll({
          ..._authHeaders(account),
          'Depth': '0',
          'Content-Type': 'application/xml; charset=utf-8',
        })
        ..body = _propfindCTagBody;

      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw CalDavException.fromStatus(response.statusCode);
      }
      final doc = XmlDocument.parse(response.body);
      return _firstLocal(doc.rootElement, 'getctag')?.innerText;
    } finally {
      client.close();
    }
  }

  @override
  Future<List<CalDavObject>> listObjects(
      NextcloudAccount account, String collectionHref) async {
    final client = _clientFor(account);
    try {
      final request = http.Request('REPORT', _resolve(account, collectionHref))
        ..headers.addAll({
          ..._authHeaders(account),
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        })
        ..body = _reportAllObjectsBody;

      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw CalDavException.fromStatus(response.statusCode);
      }
      return _parseObjects(response.body);
    } finally {
      client.close();
    }
  }

  @override
  Future<String> putObject(
    NextcloudAccount account,
    String objectHref,
    String icalData, {
    String? ifMatchEtag,
  }) async {
    final client = _clientFor(account);
    try {
      final response = await client.put(
        _resolve(account, objectHref),
        headers: {
          ..._authHeaders(account),
          'Content-Type': 'text/calendar; charset=utf-8',
          'If-Match': ?ifMatchEtag,
        },
        body: icalData,
      );
      if (response.statusCode != 201 && response.statusCode != 204) {
        throw CalDavException.fromStatus(response.statusCode);
      }
      // Neues ETag aus dem Header; Nextcloud liefert es i.d.R. zurück.
      return response.headers['etag'] ?? '';
    } finally {
      client.close();
    }
  }

  @override
  Future<void> deleteObject(
    NextcloudAccount account,
    String objectHref, {
    String? ifMatchEtag,
  }) async {
    final client = _clientFor(account);
    try {
      final response = await client.delete(
        _resolve(account, objectHref),
        headers: {
          ..._authHeaders(account),
          'If-Match': ?ifMatchEtag,
        },
      );
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 404) {
        throw CalDavException.fromStatus(response.statusCode);
      }
    } finally {
      client.close();
    }
  }

  // ---- XML-Parsing (namespace-agnostisch über lokale Tag-Namen) ----

  List<CalDavCollection> _parseCollections(String body) {
    final doc = XmlDocument.parse(body);
    final result = <CalDavCollection>[];

    for (final response in _allLocal(doc.rootElement, 'response')) {
      final href = _firstLocal(response, 'href')?.innerText.trim();
      if (href == null) continue;

      final resourceType = _firstLocal(response, 'resourcetype');
      final isCalendar = resourceType != null &&
          _allLocal(resourceType, 'calendar').isNotEmpty;
      if (!isCalendar) continue; // Home-Collection & Sonstiges überspringen.

      final comps = _allLocal(response, 'comp')
          .map((e) => e.getAttribute('name')?.toUpperCase())
          .whereType<String>()
          .toSet();

      final displayName = _firstLocal(response, 'displayname')?.innerText.trim();
      final color = _firstLocal(response, 'calendar-color')?.innerText.trim();
      final ctag = _firstLocal(response, 'getctag')?.innerText.trim();

      result.add(CalDavCollection(
        href: href,
        displayName: (displayName == null || displayName.isEmpty)
            ? _hrefName(href)
            : displayName,
        color: (color == null || color.isEmpty) ? null : color,
        ctag: ctag,
        supportsEvents: comps.contains('VEVENT'),
        supportsTodos: comps.contains('VTODO'),
      ));
    }
    return result;
  }

  List<CalDavObject> _parseObjects(String body) {
    final doc = XmlDocument.parse(body);
    final result = <CalDavObject>[];
    for (final response in _allLocal(doc.rootElement, 'response')) {
      final href = _firstLocal(response, 'href')?.innerText.trim();
      final etag = _firstLocal(response, 'getetag')?.innerText.trim() ?? '';
      final data = _firstLocal(response, 'calendar-data')?.innerText;
      if (href == null || data == null || data.trim().isEmpty) continue;
      result.add(CalDavObject(href: href, etag: etag, icalData: data));
    }
    return result;
  }

  /// Letztes Pfadsegment eines href als Fallback-Anzeigename.
  String _hrefName(String href) {
    final parts = href.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? href : parts.last;
  }

  Iterable<XmlElement> _allLocal(XmlElement root, String local) =>
      root.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  XmlElement? _firstLocal(XmlElement root, String local) {
    for (final e in root.descendants.whereType<XmlElement>()) {
      if (e.name.local == local) return e;
    }
    return null;
  }
}

const _propfindCollectionsBody = '''
<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/"
            xmlns:c="urn:ietf:params:xml:ns:caldav"
            xmlns:ic="http://apple.com/ns/ical/">
  <d:prop>
    <d:displayname />
    <d:resourcetype />
    <cs:getctag />
    <c:supported-calendar-component-set />
    <ic:calendar-color />
  </d:prop>
</d:propfind>''';

const _propfindCTagBody = '''
<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
  <d:prop><cs:getctag /></d:prop>
</d:propfind>''';

const _reportAllObjectsBody = '''
<?xml version="1.0" encoding="utf-8" ?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:getetag />
    <c:calendar-data />
  </d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR" />
  </c:filter>
</c:calendar-query>''';
