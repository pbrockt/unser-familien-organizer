import 'dart:convert';

import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/features/fitness/fitness_webdav.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _account = NextcloudAccount(
  baseUrl: 'https://cloud.example.de',
  username: 'pb',
  appPassword: 'geheim',
);

/// Antwort einer Nextcloud auf PROPFIND. Bewusst mit `d:`-Präfix und einem zweiten
/// Namensraum (`oc:`), wie es echte Server liefern.
const _multistatus = '''<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">
  <d:response>
    <d:href>/remote.php/webdav/Gesundheit/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/></d:resourcetype>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/webdav/Gesundheit/Trainings/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/></d:resourcetype>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/webdav/Gesundheit/2026-08-25.md</d:href>
    <d:propstat><d:prop>
      <d:resourcetype/>
      <d:getetag>&quot;abc123&quot;</d:getetag>
      <d:getcontentlength>412</d:getcontentlength>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/webdav/Gesundheit/Mein%20Ordner/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/></d:resourcetype>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';

void main() {
  group('WebDavClient.list', () {
    test('liest Ordner und Dateien aus der Antwort', () async {
      late http.BaseRequest gesehen;
      final client = WebDavClient(
        httpClient: MockClient((request) async {
          gesehen = request;
          return http.Response(_multistatus, 207);
        }),
      );

      final entries = await client.list(_account, '/Gesundheit');

      expect(gesehen.method, 'PROPFIND');
      expect(gesehen.headers['Depth'], '1');
      expect(
        gesehen.headers['Authorization'],
        'Basic ${base64Encode(utf8.encode('pb:geheim'))}',
      );

      // Der angefragte Ordner selbst darf nicht mit in der Liste stehen.
      expect(entries.map((e) => e.path), isNot(contains('/Gesundheit')));

      final ordner = entries.where((e) => e.isDirectory).map((e) => e.name).toList();
      expect(ordner, containsAll(['Trainings', 'Mein Ordner']),
          reason: 'Prozentkodierte Namen müssen dekodiert werden');

      final datei = entries.firstWhere((e) => !e.isDirectory);
      expect(datei.name, '2026-08-25.md');
      expect(datei.path, '/Gesundheit/2026-08-25.md');
      expect(datei.etag, 'abc123', reason: 'Anführungszeichen gehören nicht in den ETag');
      expect(datei.size, 412);
    });

    test('kodiert Leerzeichen im Pfad, aber keine Schrägstriche', () async {
      late Uri gesehen;
      final client = WebDavClient(
        httpClient: MockClient((request) async {
          gesehen = request.url;
          return http.Response(_multistatus, 207);
        }),
      );

      await client.list(_account, '/Mein Ordner/Unter Ordner');

      expect(gesehen.path, contains('Mein%20Ordner/Unter%20Ordner'));
      expect(gesehen.path, startsWith('/remote.php/webdav/'));
    });

    test('meldet abgelehnte Zugangsdaten verständlich', () async {
      final client = WebDavClient(
        httpClient: MockClient((_) async => http.Response('nope', 401)),
      );
      expect(
        () => client.list(_account, '/x'),
        throwsA(isA<WebDavException>().having(
          (e) => e.message,
          'message',
          contains('App-Passwort'),
        )),
      );
    });

    test('meldet einen fehlenden Ordner mit Namen', () async {
      final client = WebDavClient(
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      expect(
        () => client.list(_account, '/Gibtsnicht'),
        throwsA(isA<WebDavException>().having(
          (e) => e.message,
          'message',
          contains('Gibtsnicht'),
        )),
      );
    });
  });

  group('WebDavClient.read', () {
    test('gibt den Dateiinhalt als Text zurück', () async {
      final client = WebDavClient(
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          return http.Response.bytes(utf8.encode('Höhenmeter: 412'), 200);
        }),
      );
      expect(await client.read(_account, '/a.md'), 'Höhenmeter: 412',
          reason: 'Umlaute müssen als UTF-8 dekodiert werden');
    });
  });
}
