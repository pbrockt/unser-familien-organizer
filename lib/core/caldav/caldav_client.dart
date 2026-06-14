import '../auth/nextcloud_account.dart';
import 'caldav_sharing.dart';

/// Eine CalDAV-Collection (Kalender oder Aufgaben-/Einkaufsliste).
class CalDavCollection {
  const CalDavCollection({
    required this.href,
    required this.displayName,
    this.color,
    this.ctag,
    this.supportsEvents = false,
    this.supportsTodos = false,
  });

  /// Pfad relativ zur Instanz, z.B.
  /// `/remote.php/dav/calendars/anna/familie/`.
  final String href;
  final String displayName;

  /// Farbe der Collection (Nextcloud-Kalenderfarbe), Hex z.B. `#RRGGBB`.
  final String? color;

  /// Collection-Tag — ändert sich, sobald sich irgendein Element ändert.
  /// Basis für den Delta-Sync (siehe SyncEngine).
  final String? ctag;

  final bool supportsEvents; // VEVENT
  final bool supportsTodos; // VTODO
}

/// Ein einzelnes CalDAV-Objekt (roher iCalendar-Body + ETag).
class CalDavObject {
  const CalDavObject({
    required this.href,
    required this.etag,
    required this.icalData,
  });

  final String href;

  /// Entity-Tag zur Konflikterkennung beim Schreiben.
  final String etag;

  /// Roher iCalendar-Inhalt (VEVENT/VTODO), wird vom IcalParser geparst.
  final String icalData;
}

/// Low-Level CalDAV-Client gegen Nextcloud (RFC 4791).
///
/// ⚠️ KRITISCHER KERN (Phase 2). Erst wenn diese Methoden stehen, können
/// die UI-Phasen (Kalender, Aufgaben, Einkauf) darauf aufsetzen.
///
/// Zu implementieren:
///  - PROPFIND → Collections (Kalender/Listen) entdecken
///  - REPORT   → Objekte in einem Zeitraum / komplette Collection
///  - GET      → einzelnes Objekt
///  - PUT      → erstellen/aktualisieren (mit If-Match ETag)
///  - DELETE   → löschen
///  - CTag/ETag → Änderungs- und Konflikterkennung
abstract class CalDavClient {
  /// Alle Kalender-/Aufgaben-Collections des Kontos auflisten (PROPFIND).
  Future<List<CalDavCollection>> listCollections(NextcloudAccount account);

  /// Alle Objekte einer Collection laden (REPORT / calendar-query).
  Future<List<CalDavObject>> listObjects(
    NextcloudAccount account,
    String collectionHref,
  );

  /// Geändertes/neues Objekt schreiben (PUT). Gibt das neue ETag zurück.
  /// Bei [ifMatchEtag] != null wird ein optimistisches Locking erzwungen.
  Future<String> putObject(
    NextcloudAccount account,
    String objectHref,
    String icalData, {
    String? ifMatchEtag,
  });

  /// Objekt löschen (DELETE).
  Future<void> deleteObject(
    NextcloudAccount account,
    String objectHref, {
    String? ifMatchEtag,
  });

  /// Aktuelles CTag einer Collection abfragen, um billig zu prüfen,
  /// ob sich seit dem letzten Sync etwas geändert hat.
  Future<String?> fetchCTag(
    NextcloudAccount account,
    String collectionHref,
  );

  /// Legt eine neue Kalender-/Aufgaben-Collection an (MKCALENDAR).
  Future<void> createCalendar(
    NextcloudAccount account, {
    required String displayName,
    required bool events,
    required bool todos,
    String? color,
  });

  /// Benennt eine Collection um (PROPPATCH displayname).
  Future<void> renameCalendar(
    NextcloudAccount account,
    String collectionHref,
    String displayName,
  );

  /// Löscht eine Collection samt Inhalt (DELETE).
  Future<void> deleteCalendar(
    NextcloudAccount account,
    String collectionHref,
  );

  // ---- Freigabe (CalDAV-Sharing) ----

  /// Sucht Nextcloud-Benutzer (Principals) per Name/E-Mail. Eine vollständige
  /// Liste aller Benutzer ist für Nicht-Admins nicht möglich.
  Future<List<Principal>> searchPrincipals(
    NextcloudAccount account,
    String query,
  );

  /// Listet die aktuellen Freigaben einer Collection.
  Future<List<CollectionShare>> listShares(
    NextcloudAccount account,
    String collectionHref,
  );

  /// Gibt eine Collection für einen Principal frei (oder ändert die Rechte).
  Future<void> setShare(
    NextcloudAccount account,
    String collectionHref, {
    required String shareHref,
    required bool readWrite,
  });

  /// Entfernt eine Freigabe.
  Future<void> removeShare(
    NextcloudAccount account,
    String collectionHref, {
    required String shareHref,
  });
}
