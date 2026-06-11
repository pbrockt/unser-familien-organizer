import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/auth/nextcloud_account.dart';

NextcloudAccount _acc(String url) => NextcloudAccount(
      baseUrl: url,
      username: ' anna ',
      appPassword: 'pw',
    ).normalized();

void main() {
  group('NextcloudAccount.normalized URL', () {
    test('nur Domain ohne Schema → https:// ergänzt', () {
      expect(_acc('pb.lah-cx.de').baseUrl, 'https://pb.lah-cx.de');
    });

    test('Domain mit https bleibt erhalten', () {
      expect(_acc('https://pb.lah-cx.de').baseUrl, 'https://pb.lah-cx.de');
    });

    test('volle DAV-URL wird auf die Basis gekürzt', () {
      expect(
        _acc('https://pb.lah-cx.de/remote.php/dav').baseUrl,
        'https://pb.lah-cx.de',
      );
    });

    test('volle Kalender-URL wird auf die Basis gekürzt', () {
      expect(
        _acc('https://pb.lah-cx.de/remote.php/dav/calendars/anna/').baseUrl,
        'https://pb.lah-cx.de',
      );
    });

    test('doppeltes Schema wird repariert', () {
      expect(
        _acc('https://https://pb.lah-cx.de').baseUrl,
        'https://pb.lah-cx.de',
      );
    });

    test('Slash am Ende wird entfernt', () {
      expect(_acc('https://pb.lah-cx.de/').baseUrl, 'https://pb.lah-cx.de');
    });

    test('Unterverzeichnis bleibt erhalten', () {
      expect(
        _acc('https://host.de/nextcloud/remote.php/dav').baseUrl,
        'https://host.de/nextcloud',
      );
    });

    test('http bleibt http', () {
      expect(_acc('http://192.168.1.5:8080').baseUrl, 'http://192.168.1.5:8080');
    });

    test('berechnet korrekte calendarHome-URL', () {
      expect(
        _acc('pb.lah-cx.de').calendarHome,
        'https://pb.lah-cx.de/remote.php/dav/calendars/anna/',
      );
    });
  });
}
