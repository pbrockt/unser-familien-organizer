import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'nextcloud_account.dart';

/// Ergebnis des Login-Flow-Starts: die Browser-URL zum Anmelden und die
/// Poll-Daten, über die die App auf den Abschluss wartet.
class LoginFlowInit {
  const LoginFlowInit({
    required this.loginUrl,
    required this.pollToken,
    required this.pollEndpoint,
  });

  final String loginUrl;
  final String pollToken;
  final String pollEndpoint;
}

/// Implementiert den Nextcloud **Login Flow v2**: Der Nutzer meldet sich im
/// Browser an, die App erhält automatisch ein App-Passwort (nie das
/// Hauptpasswort).
class NextcloudLoginService {
  const NextcloudLoginService();

  http.Client _client(bool allowInsecure) {
    if (!allowInsecure) return http.Client();
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(inner);
  }

  /// Bereinigt die eingegebene Adresse auf die Server-Basis (ohne Pfad/Slash).
  String normalizeBase(String url) => NextcloudAccount(
        baseUrl: url,
        username: '',
        appPassword: '',
      ).normalized().baseUrl;

  /// Startet den Login-Flow und liefert die Browser-URL + Poll-Daten.
  Future<LoginFlowInit> start(String baseUrl,
      {bool allowInsecure = false}) async {
    final client = _client(allowInsecure);
    try {
      final resp = await client.post(
        Uri.parse('$baseUrl/index.php/login/v2'),
        headers: const {
          // Wird Nextcloud als App-Name angezeigt.
          'User-Agent': 'FamilyPlanner',
          'Accept': 'application/json',
        },
      );
      if (resp.statusCode != 200) {
        throw HttpException('Server antwortete mit ${resp.statusCode}. '
            'Ist die Adresse korrekt?');
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final poll = json['poll'] as Map<String, dynamic>;
      return LoginFlowInit(
        loginUrl: json['login'] as String,
        pollToken: poll['token'] as String,
        pollEndpoint: poll['endpoint'] as String,
      );
    } on FormatException {
      throw const HttpException(
          'Unerwartete Antwort – ist das eine Nextcloud-Adresse?');
    } finally {
      client.close();
    }
  }

  /// Pollt bis zur erfolgreichen Anmeldung. Gibt das Konto zurück, oder `null`
  /// bei Abbruch/Timeout.
  Future<NextcloudAccount?> poll(
    LoginFlowInit init, {
    required bool Function() isCancelled,
    bool allowInsecure = false,
    Duration interval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final client = _client(allowInsecure);
    final deadline = DateTime.now().add(timeout);
    try {
      while (!isCancelled() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(interval);
        if (isCancelled()) return null;
        final resp = await client.post(
          Uri.parse(init.pollEndpoint),
          body: {'token': init.pollToken},
        );
        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          return NextcloudAccount(
            baseUrl: json['server'] as String,
            username: json['loginName'] as String,
            appPassword: json['appPassword'] as String,
            allowInsecureCert: allowInsecure,
          ).normalized();
        }
        // 404 → noch nicht angemeldet, weiter warten.
      }
    } finally {
      client.close();
    }
    return null;
  }
}
