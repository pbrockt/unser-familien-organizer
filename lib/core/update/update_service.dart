import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Infos zu einer verfügbaren neueren Version (aus dem neuesten GitHub-Release).
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.apkUrl,
    required this.releaseUrl,
    this.notes,
  });

  final String version;
  final String apkUrl;
  final String releaseUrl;
  final String? notes;
}

/// Prüft auf neue App-Versionen über die GitHub-Releases-API und lädt das APK
/// bei Bedarf direkt in der App herunter und startet die Installation.
class UpdateService {
  const UpdateService();

  static const _owner = 'pbrockt';
  static const _repo = 'unser-familien-organizer';
  static const _userAgent = 'Unser Familien-Organizer';

  static const releasesUrl =
      'https://github.com/$_owner/$_repo/releases';

  /// Liefert [UpdateInfo], wenn das neueste Release neuer ist als die laufende
  /// Version – sonst `null`.
  Future<UpdateInfo?> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final resp = await http.get(
      Uri.parse(
          'https://api.github.com/repos/$_owner/$_repo/releases/latest'),
      headers: const {
        'User-Agent': _userAgent,
        'Accept': 'application/vnd.github+json',
      },
    );
    if (resp.statusCode != 200) return null;
    final json = _decode(resp.body);
    if (json == null) return null;

    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    if (tag.isEmpty || !isNewerVersion(tag, info.version)) return null;

    final assets = (json['assets'] as List?) ?? const [];
    String? apkUrl;
    for (final a in assets) {
      final name = (a as Map)['name'] as String? ?? '';
      if (name.toLowerCase().endsWith('.apk')) {
        apkUrl = a['browser_download_url'] as String?;
        break;
      }
    }
    if (apkUrl == null) return null;

    return UpdateInfo(
      version: tag.replaceFirst(RegExp(r'^v'), ''),
      apkUrl: apkUrl,
      releaseUrl: (json['html_url'] as String?) ?? releasesUrl,
      notes: json['body'] as String?,
    );
  }

  /// Lädt das APK herunter (mit Fortschritt 0..1) und öffnet danach den
  /// System-Installer. Nur auf Android sinnvoll.
  Future<void> downloadAndInstall(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    // App-spezifisches externes Verzeichnis (vom FileProvider von open_filex
    // abgedeckt), mit Cache-Fallback.
    final dir =
        await getExternalStorageDirectory() ?? await getApplicationCacheDirectory();
    final file = File('${dir.path}/UnserFamilienOrganizer-${info.version}.apk');

    final request = http.Request('GET', Uri.parse(info.apkUrl))
      ..headers['User-Agent'] = _userAgent;
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw HttpException('Download fehlgeschlagen (${response.statusCode}).');
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
    } finally {
      await sink.close();
    }

    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw Exception('Installer konnte nicht geöffnet werden: '
          '${result.message}');
    }
  }

  Map<String, dynamic>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// Vergleicht zwei Versionsstrings (z.B. `0.30.4` vs `0.30.3+33`). Build-Suffix
/// nach `+` und ein führendes `v` werden ignoriert.
@visibleForTesting
bool isNewerVersion(String latest, String current) {
  List<int> parse(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split('+')
      .first
      .split('.')
      .map((p) => int.tryParse(RegExp(r'\d+').stringMatch(p) ?? '') ?? 0)
      .toList();
  final a = parse(latest);
  final b = parse(current);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

final updateServiceProvider =
    Provider<UpdateService>((ref) => const UpdateService());
