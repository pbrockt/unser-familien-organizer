import '../auth/nextcloud_account.dart';
import '../cache/caldav_cache.dart';
import 'caldav_client.dart';

/// Ergebnis eines Ladevorgangs: Collections + Objekte und ob die Daten aus
/// dem Offline-Cache stammen.
class CalDavSnapshot {
  const CalDavSnapshot(this.collections, this.objects, {required this.fromCache});

  final List<CalDavCollection> collections;
  final Map<String, List<CalDavObject>> objects;
  final bool fromCache;

  List<CalDavObject> objectsOf(String collectionHref) =>
      objects[collectionHref] ?? const [];
}

/// Lädt CalDAV-Daten vom Server und spiegelt sie in den lokalen Cache.
/// Schlägt das Netzwerk fehl, wird der zuletzt gespeicherte Stand geliefert.
class CalDavRepository {
  CalDavRepository(this._client, this._cache);

  final CalDavClient _client;
  final CalDavCache _cache;

  String _key(NextcloudAccount a) => '${a.baseUrl}|${a.username}';

  Future<CalDavSnapshot> load(NextcloudAccount account) async {
    try {
      final collections = await _client.listCollections(account);
      final objects = <String, List<CalDavObject>>{};
      for (final c in collections) {
        objects[c.href] = await _client.listObjects(account, c.href);
      }
      await _cache.save(_key(account), CachedSnapshot(collections, objects));
      return CalDavSnapshot(collections, objects, fromCache: false);
    } catch (e) {
      // Offline oder Serverfehler → zuletzt gecachten Stand zeigen.
      final cached = await _cache.load(_key(account));
      if (cached != null) {
        return CalDavSnapshot(cached.collections, cached.objects,
            fromCache: true);
      }
      rethrow; // Kein Cache vorhanden → Fehler durchreichen.
    }
  }
}
