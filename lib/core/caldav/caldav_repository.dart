import 'dart:io';

import 'package:http/http.dart' as http;

import '../auth/nextcloud_account.dart';
import '../cache/caldav_cache.dart';
import 'caldav_client.dart';

/// Ergebnis eines Ladevorgangs: Collections + Objekte und ob die Daten aus
/// dem Offline-Cache stammen.
class CalDavSnapshot {
  const CalDavSnapshot(this.collections, this.objects,
      {required this.fromCache});

  final List<CalDavCollection> collections;
  final Map<String, List<CalDavObject>> objects;
  final bool fromCache;

  List<CalDavObject> objectsOf(String collectionHref) =>
      objects[collectionHref] ?? const [];
}

/// Lädt CalDAV-Daten vom Server und spiegelt sie in den lokalen Cache.
///
/// Schreib-Operationen (PUT/DELETE) versuchen zuerst den Server; ist dieser
/// nicht erreichbar, landen sie in einer Warteschlange (SQLite) und der Cache
/// wird optimistisch aktualisiert. Beim nächsten erfolgreichen [load] wird die
/// Warteschlange automatisch abgespielt.
class CalDavRepository {
  CalDavRepository(this._client, this._cache);

  final CalDavClient _client;
  final CalDavCache _cache;

  String _key(NextcloudAccount a) => '${a.baseUrl}|${a.username}';

  String _collectionOf(String objectHref) {
    final i = objectHref.lastIndexOf('/');
    return i < 0 ? objectHref : objectHref.substring(0, i + 1);
  }

  bool _isOffline(Object e) => e is SocketException || e is http.ClientException;

  Future<CalDavSnapshot> load(NextcloudAccount account) async {
    // 1) Offline erzeugte Änderungen zuerst hochladen.
    try {
      await flushQueue(account);
    } catch (_) {
      // Weiterhin offline → später erneut.
    }

    // 2) Frisch vom Server laden …
    try {
      final collections = await _client.listCollections(account);
      final objects = <String, List<CalDavObject>>{};
      for (final c in collections) {
        objects[c.href] = await _client.listObjects(account, c.href);
      }
      await _cache.save(_key(account), CachedSnapshot(collections, objects));
      return CalDavSnapshot(collections, objects, fromCache: false);
    } catch (e) {
      // … sonst den letzten Stand aus dem Cache.
      final cached = await _cache.load(_key(account));
      if (cached != null) {
        return CalDavSnapshot(cached.collections, cached.objects,
            fromCache: true);
      }
      rethrow;
    }
  }

  /// Schreibt ein Objekt. Gibt das neue ETag zurück – oder `null`, wenn die
  /// Operation (offline) eingereiht wurde.
  Future<String?> putObject(
    NextcloudAccount account,
    String objectHref,
    String icalData, {
    String? ifMatchEtag,
  }) async {
    try {
      return await _client.putObject(account, objectHref, icalData,
          ifMatchEtag: ifMatchEtag);
    } catch (e) {
      if (!_isOffline(e)) rethrow;
      await _cache.addPendingOp(_key(account),
          kind: 'put',
          objectHref: objectHref,
          icalData: icalData,
          ifMatchEtag: ifMatchEtag);
      await _cache.upsertObject(
        _key(account),
        _collectionOf(objectHref),
        CalDavObject(href: objectHref, etag: '', icalData: icalData),
      );
      return null;
    }
  }

  /// Löscht ein Objekt. Wird offline eingereiht, falls kein Netz.
  Future<void> deleteObject(
    NextcloudAccount account,
    String objectHref, {
    String? ifMatchEtag,
  }) async {
    try {
      await _client.deleteObject(account, objectHref, ifMatchEtag: ifMatchEtag);
    } catch (e) {
      if (!_isOffline(e)) rethrow;
      await _cache.addPendingOp(_key(account),
          kind: 'delete',
          objectHref: objectHref,
          ifMatchEtag: ifMatchEtag);
      await _cache.removeObject(_key(account), objectHref);
    }
  }

  /// Spielt die Warteschlange ab. Bei weiterhin fehlender Verbindung bricht das
  /// Abspielen ab (Operationen bleiben erhalten); bei Server-Fehlern
  /// (Konflikt/nicht vorhanden) wird die Operation verworfen.
  Future<void> flushQueue(NextcloudAccount account) async {
    final key = _key(account);
    final ops = await _cache.pendingOps(key);
    for (final op in ops) {
      try {
        if (op.isPut) {
          await _client.putObject(account, op.objectHref, op.icalData ?? '',
              ifMatchEtag: op.ifMatchEtag);
        } else {
          await _client.deleteObject(account, op.objectHref,
              ifMatchEtag: op.ifMatchEtag);
        }
        await _cache.removePendingOp(op.id);
      } catch (e) {
        if (_isOffline(e)) return; // immer noch offline → später weiter
        await _cache.removePendingOp(op.id); // Konflikt/weg → verwerfen
      }
    }
  }

  Future<int> pendingCount(NextcloudAccount account) =>
      _cache.pendingCount(_key(account));
}
