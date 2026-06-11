import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../caldav/caldav_client.dart';

/// Lokal zwischengespeicherter Stand: Collections + ihre Objekte.
class CachedSnapshot {
  const CachedSnapshot(this.collections, this.objects);
  final List<CalDavCollection> collections;
  final Map<String, List<CalDavObject>> objects;
}

/// SQLite-Cache (sqflite) der CalDAV-Daten für Offline-Lesen und schnelleres
/// Anzeigen beim Start. Pro Konto wird der jeweils letzte erfolgreiche Stand
/// gehalten.
class CalDavCache {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'caldav_cache.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE collections(
            account TEXT NOT NULL,
            href TEXT NOT NULL,
            display_name TEXT,
            color TEXT,
            ctag TEXT,
            supports_events INTEGER NOT NULL,
            supports_todos INTEGER NOT NULL,
            PRIMARY KEY(account, href)
          )''');
        await db.execute('''
          CREATE TABLE objects(
            account TEXT NOT NULL,
            collection_href TEXT NOT NULL,
            object_href TEXT NOT NULL,
            etag TEXT,
            ical_data TEXT NOT NULL,
            PRIMARY KEY(account, object_href)
          )''');
      },
    );
    return _db!;
  }

  /// Ersetzt den gespeicherten Stand eines Kontos durch [snapshot].
  Future<void> save(String account, CachedSnapshot snapshot) async {
    final db = await _open();
    await db.transaction((txn) async {
      await txn
          .delete('collections', where: 'account = ?', whereArgs: [account]);
      await txn.delete('objects', where: 'account = ?', whereArgs: [account]);
      for (final c in snapshot.collections) {
        await txn.insert('collections', {
          'account': account,
          'href': c.href,
          'display_name': c.displayName,
          'color': c.color,
          'ctag': c.ctag,
          'supports_events': c.supportsEvents ? 1 : 0,
          'supports_todos': c.supportsTodos ? 1 : 0,
        });
      }
      for (final entry in snapshot.objects.entries) {
        for (final o in entry.value) {
          await txn.insert(
            'objects',
            {
              'account': account,
              'collection_href': entry.key,
              'object_href': o.href,
              'etag': o.etag,
              'ical_data': o.icalData,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });
  }

  /// Lädt den gespeicherten Stand eines Kontos, oder `null` wenn keiner da ist.
  Future<CachedSnapshot?> load(String account) async {
    final db = await _open();
    final colRows =
        await db.query('collections', where: 'account = ?', whereArgs: [account]);
    if (colRows.isEmpty) return null;

    final collections = colRows
        .map((r) => CalDavCollection(
              href: r['href'] as String,
              displayName: (r['display_name'] as String?) ?? '',
              color: r['color'] as String?,
              ctag: r['ctag'] as String?,
              supportsEvents: (r['supports_events'] as int) == 1,
              supportsTodos: (r['supports_todos'] as int) == 1,
            ))
        .toList();

    final objRows =
        await db.query('objects', where: 'account = ?', whereArgs: [account]);
    final objects = <String, List<CalDavObject>>{};
    for (final r in objRows) {
      final href = r['collection_href'] as String;
      objects.putIfAbsent(href, () => []).add(CalDavObject(
            href: r['object_href'] as String,
            etag: (r['etag'] as String?) ?? '',
            icalData: r['ical_data'] as String,
          ));
    }
    return CachedSnapshot(collections, objects);
  }
}
