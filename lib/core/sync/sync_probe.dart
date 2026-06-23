import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../auth/nextcloud_account.dart';

/// Führt einen direkten Verbindungs-Test zur Nextcloud durch und liefert einen
/// gut lesbaren Bericht (HTTP-Statuscodes, Header, Fehlertyp). Dient der
/// Fehlersuche im Sync-Diagnose-Popup – unabhängig vom normalen Sync-Pfad.
Future<String> runConnectionProbe(NextcloudAccount account) async {
  final out = StringBuffer();
  try {
    final info = await PackageInfo.fromPlatform();
    out.writeln('App: ${info.version} (${info.buildNumber})');
  } catch (_) {}
  out.writeln('Server: ${account.baseUrl}');
  out.writeln('User: ${account.username}');
  out.writeln('Insecure-Cert erlaubt: ${account.allowInsecureCert}');
  out.writeln('');

  http.Client newClient() {
    if (!account.allowInsecureCert) return http.Client();
    final inner = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(inner);
  }

  final auth = {
    'Authorization': 'Basic ${base64Encode(utf8.encode(account.credentials))}',
  };

  Future<void> probe(
    String label,
    String method,
    String url, {
    Map<String, String>? headers,
    bool withAuth = true,
  }) async {
    final client = newClient();
    out.writeln('• $label');
    out.writeln('  $method $url');
    try {
      final req = http.Request(method, Uri.parse(url))
        ..followRedirects = false
        ..headers.addAll({
          if (withAuth) ...auth,
          ...?headers,
        });
      final res = await http.Response.fromStream(
        await client.send(req),
      ).timeout(const Duration(seconds: 15));
      out.writeln('  → HTTP ${res.statusCode}');
      final interesting = ['dav', 'location', 'www-authenticate', 'server'];
      for (final h in interesting) {
        final v = res.headers[h];
        if (v != null) out.writeln('  $h: $v');
      }
      if (res.statusCode >= 400) {
        final body = res.body;
        final snippet = body.substring(
          0,
          body.length < 200 ? body.length : 200,
        );
        out.writeln('  Body: $snippet');
      }
    } catch (e) {
      out.writeln('  ✖ FEHLER ${e.runtimeType}: $e');
    } finally {
      client.close();
    }
    out.writeln('');
  }

  // 1) Erreichbarkeit (ohne Auth) – Nextcloud /status.php gibt immer JSON.
  await probe(
    'Erreichbarkeit (status.php)',
    'GET',
    '${account.baseUrl}/status.php',
    withAuth: false,
  );
  // 2) Auth + CalDAV – PROPFIND auf den Kalender-Home (207 = ok, 401 = Auth).
  await probe(
    'CalDAV (PROPFIND Kalender-Home)',
    'PROPFIND',
    account.calendarHome,
    headers: const {'Depth': '0', 'Content-Type': 'application/xml'},
  );

  return out.toString();
}
