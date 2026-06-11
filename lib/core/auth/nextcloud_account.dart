import 'dart:convert';

/// Zugangsdaten zu einer Nextcloud-Instanz.
///
/// Es wird ausschließlich ein **App-Passwort** gespeichert (nie das
/// Hauptpasswort), erzeugt über den Nextcloud Login Flow v2 oder manuell
/// in den Nextcloud-Sicherheitseinstellungen. Die Daten landen verschlüsselt
/// in `flutter_secure_storage` (Android Keystore).
class NextcloudAccount {
  const NextcloudAccount({
    required this.baseUrl,
    required this.username,
    required this.appPassword,
    this.allowInsecureCert = false,
  });

  /// Basis-URL der Instanz, z.B. `https://cloud.example.com`.
  /// Ohne abschließenden Slash gespeichert (siehe [normalized]).
  final String baseUrl;

  /// Loginname des Nutzers.
  final String username;

  /// App-Passwort (Login Flow v2), nicht das Hauptpasswort.
  final String appPassword;

  /// Bei selbst-signierten Zertifikaten (Heimserver/Unraid) erlauben,
  /// dass das TLS-Zertifikat nicht von einer offiziellen CA stammt.
  final bool allowInsecureCert;

  /// CalDAV-Wurzel des Nutzers:
  /// `https://cloud.example.com/remote.php/dav/calendars/{user}/`
  String get calendarHome => '$baseUrl/remote.php/dav/calendars/$username/';

  /// Allgemeine DAV-Basis.
  String get davBase => '$baseUrl/remote.php/dav';

  /// WebDAV-Basis für Dateien (z.B. spätere Anhänge).
  String get webdavBase => '$baseUrl/remote.php/webdav/';

  /// Rohe `user:passwort`-Credentials (Basic Auth, vom Client base64-kodiert).
  String get credentials => '$username:$appPassword';

  /// Macht aus beliebiger Nutzereingabe eine saubere Server-Basis-URL.
  ///
  /// Der Nutzer muss nur die Adresse eingeben – die App hängt den
  /// CalDAV-Pfad selbst an. Es werden u.a. abgefangen:
  ///  - fehlendes Schema           (`pb.lah-cx.de` → `https://pb.lah-cx.de`)
  ///  - doppelt eingefügtes Schema (`https://https://…` → `https://…`)
  ///  - eingefügte volle DAV-URL   (`…/remote.php/dav/…` wird abgeschnitten)
  ///  - Slash am Ende
  /// Ein evtl. Unterverzeichnis (z.B. `…/nextcloud`) bleibt erhalten.
  NextcloudAccount normalized() {
    var url = baseUrl.trim();

    // http(s):// am Anfang merken und (auch mehrfach) entfernen.
    final wantsHttp = RegExp(r'^http://').hasMatch(url);
    url = url.replaceFirst(RegExp(r'^(https?://)+'), '');

    // Alles ab dem Nextcloud-DAV-Pfad abschneiden – egal wie viel
    // der Nutzer eingefügt hat. Unterpfade davor bleiben erhalten.
    final davIndex = url.indexOf('/remote.php');
    if (davIndex != -1) {
      url = url.substring(0, davIndex);
    }

    // Slashes am Ende weg.
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    url = (wantsHttp ? 'http://' : 'https://') + url;

    return copyWith(
      baseUrl: url,
      username: username.trim(),
    );
  }

  NextcloudAccount copyWith({
    String? baseUrl,
    String? username,
    String? appPassword,
    bool? allowInsecureCert,
  }) {
    return NextcloudAccount(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      appPassword: appPassword ?? this.appPassword,
      allowInsecureCert: allowInsecureCert ?? this.allowInsecureCert,
    );
  }

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'username': username,
        'appPassword': appPassword,
        'allowInsecureCert': allowInsecureCert,
      };

  factory NextcloudAccount.fromJson(Map<String, dynamic> json) {
    return NextcloudAccount(
      baseUrl: json['baseUrl'] as String,
      username: json['username'] as String,
      appPassword: json['appPassword'] as String,
      allowInsecureCert: json['allowInsecureCert'] as bool? ?? false,
    );
  }

  String encode() => jsonEncode(toJson());

  factory NextcloudAccount.decode(String raw) =>
      NextcloudAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
