import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/auth/nextcloud_login_service.dart';

void main() {
  group('rewriteToBaseOrigin', () {
    test('schreibt internen Host auf die eingegebene Basis um, Pfad bleibt', () {
      final result = rewriteToBaseOrigin(
        'https://nextcloud.intern.lan/index.php/login/v2/poll',
        'https://cloud.example.com',
      );
      expect(result, 'https://cloud.example.com/index.php/login/v2/poll');
    });

    test('erhält Query-Parameter', () {
      final result = rewriteToBaseOrigin(
        'https://intern.lan/login/flow?token=abc&x=1',
        'https://cloud.example.com',
      );
      expect(result, 'https://cloud.example.com/login/flow?token=abc&x=1');
    });

    test('übernimmt expliziten Port der Basis', () {
      final result = rewriteToBaseOrigin(
        'https://intern.lan/poll',
        'https://cloud.example.com:8443',
      );
      expect(result, 'https://cloud.example.com:8443/poll');
    });

    test('ersetzt expliziten Port der Server-URL durch Standard-Port der Basis',
        () {
      final result = rewriteToBaseOrigin(
        'https://intern.lan:9000/poll',
        'https://cloud.example.com',
      );
      expect(result, 'https://cloud.example.com/poll');
    });

    test('übernimmt Schema der Basis (http)', () {
      final result = rewriteToBaseOrigin(
        'https://intern.lan/poll',
        'http://cloud.example.com',
      );
      expect(result, 'http://cloud.example.com/poll');
    });

    test('schreibt reine Server-Wurzel (json[server]) ohne Pfad um', () {
      final result = rewriteToBaseOrigin(
        'https://nextcloud.intern.lan',
        'https://cloud.example.com',
      );
      expect(result, 'https://cloud.example.com');
    });

    test('gibt Original zurück, wenn Basis keinen Host hat', () {
      final result = rewriteToBaseOrigin('https://intern.lan/poll', 'kaputt');
      expect(result, 'https://intern.lan/poll');
    });
  });
}
