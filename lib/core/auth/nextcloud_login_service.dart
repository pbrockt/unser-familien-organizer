import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../caldav/caldav_exception.dart';
import 'nextcloud_account.dart';

/// Ersetzt Schema + Host (+ Port) der vom Server gelieferten URL durch die der
/// vom Nutzer eingegebenen Server-Basis. Pfad und Query bleiben erhalten.
///
/// Hintergrund: Nextcloud baut die `login`/`poll`-URLs im Login Flow v2 aus
/// seiner eigenen Config (`overwrite.cli.url` / Trusted Domains / Reverse-Proxy).
/// Steht dort ein nur intern auflösbarer Name, würde die App gegen einen Host
/// pollen, den das Gerät nicht erreicht (DNS-Fehler „errno 7"). Da beide URLs
/// im Flow v2 garantiert auf demselben Server liegen, ist das Umschreiben auf
/// die tatsächlich erreichbare Adresse sicher.
@visibleForTesting
String rewriteToBaseOrigin(String returnedUrl, String base) {
  final returned = Uri.tryParse(returnedUrl);
  final baseUri = Uri.tryParse(base);
  if (returned == null || baseUri == null || !baseUri.hasAuthority) {
    return returnedUrl;
  }
  // Expliziten Port setzen: ohne ihn würde Uri.replace den Port der
  // Server-URL beibehalten. Bei Standard-Port lässt toString() ihn weg.
  final port =
      baseUri.hasPort ? baseUri.port : (baseUri.scheme == 'http' ? 80 : 443);
  return returned
      .replace(scheme: baseUri.scheme, host: baseUri.host, port: port)
      .toString();
}

/// Ergebnis des Login-Flow-Starts: die Browser-URL zum Anmelden und die
/// Poll-Daten, über die die App auf den Abschluss wartet.
class LoginFlowInit {
  const LoginFlowInit({
    required this.loginUrl,
    required this.pollToken,
    required this.pollEndpoint,
    required this.baseUrl,
  });

  final String loginUrl;
  final String pollToken;
  final String pollEndpoint;

  /// Die vom Nutzer eingegebene, erreichbare Server-Basis. Wird genutzt, um die
  /// nach dem Login vom Server gemeldete Adresse (`json['server']`) ebenfalls
  /// auf den erreichbaren Host umzuschreiben.
  final String baseUrl;
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
          'User-Agent': 'Unser Familien-Organizer',
          'Accept': 'application/json',
        },
      );
      if (resp.statusCode != 200) {
        throw CalDavException('Server antwortete mit ${resp.statusCode}. '
            'Ist die Adresse korrekt?');
      }
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final poll = json['poll'] as Map<String, dynamic>;
      // Vom Server gelieferte URLs auf die erreichbare Basis umschreiben
      // (siehe [rewriteToBaseOrigin]).
      return LoginFlowInit(
        loginUrl: rewriteToBaseOrigin(json['login'] as String, baseUrl),
        pollToken: poll['token'] as String,
        pollEndpoint: rewriteToBaseOrigin(poll['endpoint'] as String, baseUrl),
        baseUrl: baseUrl,
      );
    } on FormatException {
      throw const CalDavException(
          'Unerwartete Antwort – ist das eine Nextcloud-Adresse?');
    } on SocketException catch (e) {
      throw _networkException(e, host: Uri.tryParse(baseUrl)?.host);
    } on HandshakeException {
      throw _tlsException();
    } finally {
      client.close();
    }
  }

  /// Übersetzt einen `SocketException` in eine verständliche Meldung – wie der
  /// CalDAV-Client (DNS-Lookup vs. allgemeiner Verbindungsfehler).
  CalDavException _networkException(SocketException e, {String? host}) {
    final isLookup = e.message.toLowerCase().contains('lookup');
    final where = (host == null || host.isEmpty) ? '' : ' („$host")';
    return CalDavException(
      isLookup
          ? 'Server-Adresse nicht gefunden$where. Dein Gerät konnte diesen '
              'Namen nicht auflösen, obwohl Browser/PC es können – meist liegt '
              'das am "Privaten DNS" des Handys: Einstellungen → Verbindungen → '
              '"Privates DNS" auf "Automatisch" oder "Aus" stellen und erneut '
              'versuchen. (Bei Heimserver hinter Reverse-Proxy zusätzlich '
              'Nextcloud "overwrite.cli.url"/Trusted-Domains prüfen.)'
          : 'Keine Verbindung zum Server$where: ${e.message}',
    );
  }

  CalDavException _tlsException() => const CalDavException(
        'TLS-Zertifikat nicht vertrauenswürdig. Bei einem Heimserver mit '
        'selbst-signiertem Zertifikat die Option "Unsicheres Zertifikat '
        'erlauben" aktivieren.',
      );

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
    // Direkt nach der Rückkehr aus dem Browser ist der Netzwerk-Stack der App
    // manchmal kurz nicht bereit (DNS-Lookup schlägt fehl, obwohl Browser/PC
    // den Host auflösen können). Deshalb bei Netzwerkfehlern nicht sofort
    // abbrechen, sondern weiter pollen – erst nach mehreren Fehlern in Folge
    // melden.
    var consecutiveNetErrors = 0;
    const maxConsecutiveNetErrors = 10;
    try {
      while (!isCancelled() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(interval);
        if (isCancelled()) return null;
        final http.Response resp;
        try {
          resp = await client.post(
            Uri.parse(init.pollEndpoint),
            body: {'token': init.pollToken},
          );
        } on SocketException catch (e) {
          if (++consecutiveNetErrors >= maxConsecutiveNetErrors) {
            throw _networkException(e,
                host: Uri.tryParse(init.pollEndpoint)?.host);
          }
          continue;
        } on HandshakeException {
          throw _tlsException();
        }
        consecutiveNetErrors = 0;
        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body) as Map<String, dynamic>;
          // Auch die vom Server gemeldete Adresse auf die erreichbare Basis
          // umschreiben – sonst nutzt die spätere Synchronisation wieder den
          // intern aufgelösten Host (siehe [rewriteToBaseOrigin]).
          return NextcloudAccount(
            baseUrl: rewriteToBaseOrigin(json['server'] as String, init.baseUrl),
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
