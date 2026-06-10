/// Zugangsdaten zu einer Nextcloud-Instanz.
///
/// Es wird ausschließlich ein **App-Passwort** gespeichert (nie das
/// Hauptpasswort), erzeugt über den Nextcloud Login Flow v2. Die Daten
/// landen verschlüsselt in `flutter_secure_storage` (Android Keystore).
class NextcloudAccount {
  const NextcloudAccount({
    required this.baseUrl,
    required this.username,
    required this.appPassword,
  });

  /// Basis-URL der Instanz, z.B. `https://cloud.example.com`.
  final String baseUrl;

  /// Loginname des Nutzers.
  final String username;

  /// App-Passwort (Login Flow v2), nicht das Hauptpasswort.
  final String appPassword;

  /// CalDAV-Wurzel des Nutzers:
  /// `https://cloud.example.com/remote.php/dav/calendars/{user}/`
  String get calendarHome =>
      '$baseUrl/remote.php/dav/calendars/$username/';

  /// WebDAV-Basis für Dateien (z.B. spätere Anhänge).
  String get webdavBase => '$baseUrl/remote.php/webdav/';

  /// Basic-Auth-Header-Wert für CalDAV-Requests.
  String get basicAuthHeader {
    // base64 wird vom http-Client gesetzt; hier nur die Roh-Credentials.
    return '$username:$appPassword';
  }

  NextcloudAccount copyWith({
    String? baseUrl,
    String? username,
    String? appPassword,
  }) {
    return NextcloudAccount(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      appPassword: appPassword ?? this.appPassword,
    );
  }
}
