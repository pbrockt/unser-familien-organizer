/// Fehler beim Reden mit dem CalDAV-Server, mit benutzerfreundlicher Meldung.
class CalDavException implements Exception {
  const CalDavException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// Übersetzt einen HTTP-Status in eine verständliche deutsche Meldung.
  factory CalDavException.fromStatus(int status) {
    final msg = switch (status) {
      401 => 'Anmeldung fehlgeschlagen. Prüfe Benutzername und App-Passwort.',
      403 => 'Zugriff verweigert. Hat der Nutzer Rechte auf die Kalender?',
      404 => 'Adresse nicht gefunden. Stimmt die Nextcloud-URL?',
      405 => 'Methode nicht erlaubt. Ist das wirklich eine Nextcloud/CalDAV-URL?',
      >= 500 => 'Serverfehler ($status). Nextcloud erreichbar?',
      _ => 'Unerwartete Antwort vom Server (Status $status).',
    };
    return CalDavException(msg, statusCode: status);
  }

  @override
  String toString() => message;
}
