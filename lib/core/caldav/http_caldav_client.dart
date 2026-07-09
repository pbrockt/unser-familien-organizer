import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../auth/nextcloud_account.dart';
import 'caldav_client.dart';
import 'caldav_exception.dart';
import 'caldav_sharing.dart';

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
    NextcloudAccount account,
  ) async {
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
      final isLookup = e.message.toLowerCase().contains('lookup');
      throw CalDavException(
        isLookup
            ? 'Server-Adresse nicht gefunden. Prüfe die Adresse und ob dein '
                  'Handy diesen Server erreichen kann (richtiges WLAN/Internet).'
            : 'Keine Verbindung zum Server: ${e.message}',
      );
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
    NextcloudAccount account,
    String collectionHref,
  ) async {
    final client = _clientFor(account);
    try {
      final request =
          http.Request('PROPFIND', _resolve(account, collectionHref))
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
    NextcloudAccount account,
    String collectionHref,
  ) async {
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
        headers: {..._authHeaders(account), 'If-Match': ?ifMatchEtag},
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

  @override
  Future<void> createCalendar(
    NextcloudAccount account, {
    required String displayName,
    required bool events,
    required bool todos,
    String? color,
  }) async {
    final client = _clientFor(account);
    try {
      // Eindeutiger URL-Slug; der Anzeigename steht in displayname.
      final href = '${account.calendarHome}${const Uuid().v4()}/';
      final comps = [
        if (events) '<c:comp name="VEVENT"/>',
        if (todos) '<c:comp name="VTODO"/>',
      ].join();
      final colorXml = (color == null || color.isEmpty)
          ? ''
          : '\n      <ic:calendar-color>${_xml(color)}</ic:calendar-color>';
      final body =
          '''
<?xml version="1.0" encoding="utf-8" ?>
<c:mkcalendar xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"
              xmlns:ic="http://apple.com/ns/ical/">
  <d:set>
    <d:prop>
      <d:displayname>${_xml(displayName)}</d:displayname>$colorXml
      <c:supported-calendar-component-set>$comps</c:supported-calendar-component-set>
    </d:prop>
  </d:set>
</c:mkcalendar>''';
      final request = http.Request('MKCALENDAR', _resolve(account, href))
        ..headers.addAll(_authHeaders(account))
        ..headers['content-type'] = 'application/xml; charset=utf-8'
        ..body = body;
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 201) {
        throw CalDavException.fromStatus(response.statusCode);
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<void> renameCalendar(
    NextcloudAccount account,
    String collectionHref,
    String displayName,
  ) async {
    final client = _clientFor(account);
    try {
      final request =
          http.Request('PROPPATCH', _resolve(account, collectionHref))
            ..headers.addAll(_authHeaders(account))
            ..headers['content-type'] = 'application/xml; charset=utf-8'
            ..body =
                '''
<?xml version="1.0" encoding="utf-8" ?>
<d:propertyupdate xmlns:d="DAV:">
  <d:set>
    <d:prop><d:displayname>${_xml(displayName)}</d:displayname></d:prop>
  </d:set>
</d:propertyupdate>''';
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw CalDavException.fromStatus(response.statusCode);
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<void> deleteCalendar(
    NextcloudAccount account,
    String collectionHref,
  ) async {
    final client = _clientFor(account);
    try {
      final response = await client.delete(
        _resolve(account, collectionHref),
        headers: _authHeaders(account),
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

  // ---- Freigabe (CalDAV-Sharing) ----

  @override
  Future<List<Principal>> searchPrincipals(
    NextcloudAccount account,
    String query,
  ) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final users = await _searchPrincipalsAt(
      account,
      '/remote.php/dav/principals/users/',
      q,
      isGroup: false,
    );
    // Gruppen-Suche zusätzlich (z. B. „Eltern"); optional – Fehler ignorieren,
    // da nicht jeder Server/jede Rechtelage Gruppen-Principal-Suche erlaubt.
    var groups = const <Principal>[];
    try {
      groups = await _searchPrincipalsAt(
        account,
        '/remote.php/dav/principals/groups/',
        q,
        isGroup: true,
      );
    } catch (_) {}
    return [...groups, ...users]; // Gruppen zuerst anzeigen.
  }

  Future<List<Principal>> _searchPrincipalsAt(
    NextcloudAccount account,
    String path,
    String q, {
    required bool isGroup,
  }) async {
    final client = _clientFor(account);
    try {
      final request = http.Request('REPORT', _resolve(account, path))
        ..headers.addAll({
          ..._authHeaders(account),
          'Depth': '0',
          'Content-Type': 'application/xml; charset=utf-8',
        })
        ..body =
            '''
<?xml version="1.0" encoding="utf-8" ?>
<d:principal-property-search xmlns:d="DAV:">
  <d:property-search>
    <d:prop><d:displayname/></d:prop>
    <d:match>${_xml(q)}</d:match>
  </d:property-search>
  <d:prop><d:displayname/></d:prop>
</d:principal-property-search>''';
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw CalDavException.fromStatus(response.statusCode);
      }
      return _parsePrincipals(response.body, account, isGroup: isGroup);
    } on SocketException catch (e) {
      throw CalDavException('Keine Verbindung zum Server: ${e.message}');
    } finally {
      client.close();
    }
  }

  @override
  Future<List<String>> fetchUserGroups(NextcloudAccount account) async {
    final client = _clientFor(account);
    try {
      final principal =
          '${account.baseUrl}/remote.php/dav/principals/users/'
          '${account.username}/';
      final request = http.Request('PROPFIND', Uri.parse(principal))
        ..headers.addAll({
          ..._authHeaders(account),
          'Depth': '0',
          'Content-Type': 'application/xml; charset=utf-8',
        })
        ..body = '''
<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:">
  <d:prop><d:group-membership/></d:prop>
</d:propfind>''';
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw CalDavException.fromStatus(response.statusCode);
      }
      return parseUserGroups(response.body);
    } on SocketException catch (e) {
      throw CalDavException('Keine Verbindung zum Server: ${e.message}');
    } finally {
      client.close();
    }
  }

  @override
  Future<List<CollectionShare>> listShares(
    NextcloudAccount account,
    String collectionHref,
  ) async {
    final client = _clientFor(account);
    try {
      final request =
          http.Request('PROPFIND', _resolve(account, collectionHref))
            ..headers.addAll({
              ..._authHeaders(account),
              'Depth': '0',
              'Content-Type': 'application/xml; charset=utf-8',
            })
            ..body = '''
<?xml version="1.0" encoding="utf-8" ?>
<d:propfind xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <d:prop><oc:invite/></d:prop>
</d:propfind>''';
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 207 && response.statusCode != 200) {
        throw CalDavException.fromStatus(response.statusCode);
      }
      return _parseShares(response.body);
    } finally {
      client.close();
    }
  }

  @override
  Future<void> setShare(
    NextcloudAccount account,
    String collectionHref, {
    required String shareHref,
    required bool readWrite,
  }) {
    // Nextcloud-Format: <oc:set> mit href; <oc:read-write/> nur bei Schreibrecht
    // (Fehlen = nur lesen).
    final rw = readWrite ? '\n    <oc:read-write/>' : '';
    final body =
        '''
<?xml version="1.0" encoding="utf-8"?>
<oc:share xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <oc:set>
    <d:href>${_xml(shareHref)}</d:href>$rw
  </oc:set>
</oc:share>''';
    return _postSharing(account, collectionHref, body);
  }

  @override
  Future<void> removeShare(
    NextcloudAccount account,
    String collectionHref, {
    required String shareHref,
  }) {
    final body =
        '''
<?xml version="1.0" encoding="utf-8"?>
<oc:share xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <oc:remove>
    <d:href>${_xml(shareHref)}</d:href>
  </oc:remove>
</oc:share>''';
    return _postSharing(account, collectionHref, body);
  }

  Future<void> _postSharing(
    NextcloudAccount account,
    String collectionHref,
    String body,
  ) async {
    final client = _clientFor(account);
    try {
      final request = http.Request('POST', _resolve(account, collectionHref))
        ..headers.addAll(_authHeaders(account))
        // WICHTIG: Schlüssel klein schreiben, sonst überschreibt der body-Setter
        // des http-Pakets den Content-Type still mit text/plain. Nextclouds
        // Sharing-Plugin (apps/dav .../Sharing/Plugin.php) akzeptiert nur
        // "application/xml" oder "text/xml" – andere Werte → 501.
        ..headers['content-type'] = 'application/xml; charset=utf-8'
        ..body = body;
      final streamed = await client.send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 207) {
        throw CalDavException.fromStatus(response.statusCode);
      }
    } finally {
      client.close();
    }
  }

  /// Baut aus einem Principal-href (`…/remote.php/dav/principals/users/bob/`)
  /// den sabre-Freigabe-href `principal:principals/users/bob`.
  String _principalShareHref(String href) {
    var p = href.trim();
    if (p.startsWith('principal:')) return p;
    const marker = '/remote.php/dav/';
    final idx = p.indexOf(marker);
    if (idx != -1) p = p.substring(idx + marker.length);
    p = p.replaceAll(RegExp(r'/+$'), '');
    return 'principal:$p';
  }

  List<Principal> _parsePrincipals(
    String body,
    NextcloudAccount account, {
    required bool isGroup,
  }) {
    final doc = XmlDocument.parse(body);
    final me = account.username.toLowerCase();
    final marker = isGroup ? '/principals/groups/' : '/principals/users/';
    final seen = <String>{};
    final result = <Principal>[];
    for (final resp in _allLocal(doc.rootElement, 'response')) {
      final href = _firstLocal(resp, 'href')?.innerText.trim();
      if (href == null || !href.contains(marker)) continue;
      // Teil nach dem Marker = ID (leer = Wurzel-Collection → überspringen).
      final after = href
          .substring(href.indexOf(marker) + marker.length)
          .replaceAll(RegExp(r'/+$'), '');
      if (after.isEmpty) continue;
      final shareHref = _principalShareHref(href);
      final id = after.toLowerCase();
      if (!isGroup && id == me) continue;
      if (!seen.add(shareHref)) continue;
      final name = _firstLocal(resp, 'displayname')?.innerText.trim();
      result.add(
        Principal(
          shareHref: shareHref,
          displayName: (name == null || name.isEmpty) ? id : name,
          isGroup: isGroup,
        ),
      );
    }
    return result;
  }

  List<CollectionShare> _parseShares(String body) {
    final doc = XmlDocument.parse(body);
    final result = <CollectionShare>[];
    for (final user in _allLocal(doc.rootElement, 'user')) {
      final href = _firstLocal(user, 'href')?.innerText.trim();
      if (href == null) continue;
      final name = _firstLocal(user, 'common-name')?.innerText.trim();
      result.add(
        CollectionShare(
          shareHref: href,
          displayName: (name == null || name.isEmpty) ? _hrefName(href) : name,
          readWrite: _allLocal(user, 'read-write').isNotEmpty,
        ),
      );
    }
    return result;
  }

  /// Escaped Text für XML-Bodies.
  String _xml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ---- XML-Parsing (namespace-agnostisch über lokale Tag-Namen) ----

  List<CalDavCollection> _parseCollections(String body) {
    final doc = XmlDocument.parse(body);
    final result = <CalDavCollection>[];

    for (final response in _allLocal(doc.rootElement, 'response')) {
      final href = _firstLocal(response, 'href')?.innerText.trim();
      if (href == null) continue;

      final resourceType = _firstLocal(response, 'resourcetype');
      final isCalendar =
          resourceType != null &&
          _allLocal(resourceType, 'calendar').isNotEmpty;
      if (!isCalendar) continue; // Home-Collection & Sonstiges überspringen.

      final comps = _allLocal(response, 'comp')
          .map((e) => e.getAttribute('name')?.toUpperCase())
          .whereType<String>()
          .toSet();

      final displayName = _firstLocal(
        response,
        'displayname',
      )?.innerText.trim();
      final color = _firstLocal(response, 'calendar-color')?.innerText.trim();
      final ctag = _firstLocal(response, 'getctag')?.innerText.trim();

      result.add(
        CalDavCollection(
          href: href,
          displayName: (displayName == null || displayName.isEmpty)
              ? _hrefName(href)
              : displayName,
          color: (color == null || color.isEmpty) ? null : color,
          ctag: ctag,
          supportsEvents: comps.contains('VEVENT'),
          supportsTodos: comps.contains('VTODO'),
        ),
      );
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

  Iterable<XmlElement> _allLocal(XmlElement root, String local) => root
      .descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == local);

  XmlElement? _firstLocal(XmlElement root, String local) {
    for (final e in root.descendants.whereType<XmlElement>()) {
      if (e.name.local == local) return e;
    }
    return null;
  }
}

/// Extrahiert die Gruppen-IDs aus einer DAV `group-membership`-Antwort
/// (`…/principals/groups/<id>/`). Namespace-agnostisch, reine Funktion (testbar).
List<String> parseUserGroups(String body) {
  final doc = XmlDocument.parse(body);
  const marker = '/principals/groups/';
  final out = <String>[];
  final seen = <String>{};
  final hrefs = doc.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'group-membership')
      .expand((gm) => gm.descendants.whereType<XmlElement>())
      .where((e) => e.name.local == 'href');
  for (final href in hrefs) {
    final h = href.innerText.trim();
    final i = h.indexOf(marker);
    if (i < 0) continue;
    final id = h.substring(i + marker.length).replaceAll(RegExp(r'/+$'), '');
    if (id.isEmpty) continue;
    if (seen.add(id.toLowerCase())) out.add(id);
  }
  return out;
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
