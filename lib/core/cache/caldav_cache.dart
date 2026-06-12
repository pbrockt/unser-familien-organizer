import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../caldav/caldav_client.dart';

/// Lokal zwischengespeicherter Stand: Collections + ihre Objekte.
class CachedSnapshot {
  const CachedSnapshot(this.collections, this.objects);
  final List<CalDavCollection> collections;
  final Map<String, List<CalDavObject>> objects;
}

/// Eine ausstehende (offline erzeugte) Schreib-Operation.
class PendingOp {
  const PendingOp({
    required this.id,
    required this.kind, // 'put' | 'delete'
    required this.objectHref,
    this.icalData,
    this.ifMatchEtag,
  });

  final int id;
  final String kind;
  final String objectHref;
  final String? icalData;
  final String? ifMatchEtag;

  bool get isPut => kind == 'put';
}

/// SQLite-Cache (sqflite) der CalDAV-Daten: Offline-Lesen, schnelles Anzeigen
/// und eine Warteschlange für offline erzeugte Schreib-Operationen.
class CalDavCache {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'caldav_cache.db'),
      version: 2,
      onCreate: (db, version) async {
        await _createCollections(db);
        await _createObjects(db);
        await _createPendingOps(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createPendingOps(db);
      },
    );
    return _db!;
  }

  Future<void> _createCollections(Database db) => db.execute('''
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

  Future<void> _createObjects(Database db) => db.execute('''
        CREATE TABLE objects(
          account TEXT NOT NULL,
          collection_href TEXT NOT NULL,
          object_href TEXT NOT NULL,
          etag TEXT,
          ical_data TEXT NOT NULL,
          PRIMARY KEY(account, object_href)
        )''');

  Future<void> _createPendingOps(Database db) => db.execute('''
        CREATE TABLE pending_ops(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          account TEXT NOT NULL,
          kind TEXT NOT NULL,
          object_href TEXT NOT NULL,
          ical_data TEXT,
          if_match_etag TEXT,
          created_at INTEGER NOT NULL
        )''');

  // ---- Snapshot (Collections + Objekte) ----

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

  Future<CachedSnapshot?> load(String account) async {
    final db = await _open();
    final colRows = await db
        .query('collections', where: 'account = ?', whereArgs: [account]);
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

  /// Optimistisches Einfügen/Ersetzen eines Objekts (für Offline-Änderungen).
  Future<void> upsertObject(
    String account,
    String collectionHref,
    CalDavObject object,
  ) async {
    final db = await _open();
    await db.insert(
      'objects',
      {
        'account': account,
        'collection_href': collectionHref,
        'object_href': object.href,
        'etag': object.etag,
        'ical_data': object.icalData,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeObject(String account, String objectHref) async {
    final db = await _open();
    await db.delete('objects',
        where: 'account = ? AND object_href = ?',
        whereArgs: [account, objectHref]);
  }

  // ---- Warteschlange (pending ops) ----

  Future<void> addPendingOp(
    String account, {
    required String kind,
    required String objectHref,
    String? icalData,
    String? ifMatchEtag,
  }) async {
    final db = await _open();
    await db.insert('pending_ops', {
      'account': account,
      'kind': kind,
      'object_href': objectHref,
      'ical_data': icalData,
      'if_match_etag': ifMatchEtag,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<PendingOp>> pendingOps(String account) async {
    final db = await _open();
    final rows = await db.query('pending_ops',
        where: 'account = ?', whereArgs: [account], orderBy: 'id ASC');
    return rows
        .map((r) => PendingOp(
              id: r['id'] as int,
              kind: r['kind'] as String,
              objectHref: r['object_href'] as String,
              icalData: r['ical_data'] as String?,
              ifMatchEtag: r['if_match_etag'] as String?,
            ))
        .toList();
  }

  Future<void> removePendingOp(int id) async {
    final db = await _open();
    await db.delete('pending_ops', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> pendingCount(String account) async {
    final db = await _open();
    final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM pending_ops WHERE account = ?', [account]);
    return Sqflite.firstIntValue(rows) ?? 0;
  }
}
