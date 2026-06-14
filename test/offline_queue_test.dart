import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/core/cache/caldav_cache.dart';
import 'package:family_planner/core/caldav/caldav_client.dart';
import 'package:family_planner/core/caldav/caldav_repository.dart';
import 'package:family_planner/core/caldav/caldav_sharing.dart';

/// In-Memory-Cache ohne SQLite (überschreibt die genutzten Methoden).
class _FakeCache extends CalDavCache {
  final List<PendingOp> ops = [];
  int _nextId = 1;
  final Map<String, CalDavObject> objects = {};

  @override
  Future<void> addPendingOp(String account,
      {required String kind,
      required String objectHref,
      String? icalData,
      String? ifMatchEtag}) async {
    ops.add(PendingOp(
        id: _nextId++,
        kind: kind,
        objectHref: objectHref,
        icalData: icalData,
        ifMatchEtag: ifMatchEtag));
  }

  @override
  Future<List<PendingOp>> pendingOps(String account) async => List.of(ops);

  @override
  Future<void> removePendingOp(int id) async =>
      ops.removeWhere((o) => o.id == id);

  @override
  Future<int> pendingCount(String account) async => ops.length;

  @override
  Future<void> upsertObject(
          String account, String collectionHref, CalDavObject object) async =>
      objects[object.href] = object;

  @override
  Future<void> removeObject(String account, String objectHref) async =>
      objects.remove(objectHref);
}

/// Fake-Client mit umschaltbarem Offline-Zustand.
class _FakeClient implements CalDavClient {
  bool offline = false;
  final List<String> puts = [];
  final List<String> deletes = [];

  @override
  Future<List<CalDavCollection>> listCollections(NextcloudAccount a) async =>
      [];

  @override
  Future<List<CalDavObject>> listObjects(
          NextcloudAccount a, String href) async =>
      [];

  @override
  Future<String> putObject(NextcloudAccount a, String href, String ical,
      {String? ifMatchEtag}) async {
    if (offline) throw const SocketException('offline');
    puts.add(href);
    return 'etag-new';
  }

  @override
  Future<void> deleteObject(NextcloudAccount a, String href,
      {String? ifMatchEtag}) async {
    if (offline) throw const SocketException('offline');
    deletes.add(href);
  }

  @override
  Future<String?> fetchCTag(NextcloudAccount a, String href) async => null;

  @override
  Future<List<Principal>> searchPrincipals(NextcloudAccount a, String q)
      async => const [];

  @override
  Future<List<CollectionShare>> listShares(NextcloudAccount a, String h)
      async => const [];

  @override
  Future<void> setShare(NextcloudAccount a, String h,
      {required String shareHref, required bool readWrite}) async {}

  @override
  Future<void> removeShare(NextcloudAccount a, String h,
      {required String shareHref}) async {}

  @override
  Future<void> createCalendar(NextcloudAccount a,
      {required String displayName,
      required bool events,
      required bool todos,
      String? color}) async {}
}

void main() {
  final account = const NextcloudAccount(
      baseUrl: 'https://x', username: 'u', appPassword: 'p');

  late _FakeClient client;
  late _FakeCache cache;
  late CalDavRepository repo;

  setUp(() {
    client = _FakeClient();
    cache = _FakeCache();
    repo = CalDavRepository(client, cache);
  });

  test('Offline-PUT wird eingereiht und optimistisch gecacht', () async {
    client.offline = true;
    final etag =
        await repo.putObject(account, '/cal/u/personal/a.ics', 'ICAL');
    expect(etag, isNull);
    expect(await repo.pendingCount(account), 1);
    expect(cache.objects.containsKey('/cal/u/personal/a.ics'), isTrue);
  });

  test('flushQueue spielt nach Wiederverbindung ab', () async {
    client.offline = true;
    await repo.putObject(account, '/cal/u/personal/a.ics', 'ICAL');
    await repo.deleteObject(account, '/cal/u/personal/b.ics');
    expect(await repo.pendingCount(account), 2);

    client.offline = false;
    await repo.flushQueue(account);
    expect(await repo.pendingCount(account), 0);
    expect(client.puts, contains('/cal/u/personal/a.ics'));
    expect(client.deletes, contains('/cal/u/personal/b.ics'));
  });

  test('flush bei weiterhin offline behält die Queue', () async {
    client.offline = true;
    await repo.putObject(account, '/cal/u/personal/a.ics', 'ICAL');
    await repo.flushQueue(account); // immer noch offline
    expect(await repo.pendingCount(account), 1);
  });

  test('Online-PUT geht direkt durch (keine Queue)', () async {
    final etag =
        await repo.putObject(account, '/cal/u/personal/c.ics', 'ICAL');
    expect(etag, 'etag-new');
    expect(await repo.pendingCount(account), 0);
  });
}
