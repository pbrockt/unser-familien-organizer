import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/core/cache/caldav_cache.dart';
import 'package:family_planner/core/caldav/caldav_client.dart';
import 'package:family_planner/core/caldav/caldav_exception.dart';
import 'package:family_planner/core/caldav/caldav_repository.dart';
import 'package:family_planner/core/caldav/caldav_sharing.dart';

class _FakeCache extends CalDavCache {
  final List<PendingOp> ops = [];
  int _nextId = 1;

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
  Future<void> removePendingOp(int id) async => ops.removeWhere((o) => o.id == id);
  @override
  Future<int> pendingCount(String account) async => ops.length;
  @override
  Future<void> upsertObject(
      String account, String collectionHref, CalDavObject object) async {}
  @override
  Future<void> removeObject(String account, String objectHref) async {}
}

class _FakeClient implements CalDavClient {
  String mode = 'ok'; // ok | offline | conflict
  int forcedPuts = 0;

  @override
  Future<String> putObject(NextcloudAccount a, String href, String ical,
      {String? ifMatchEtag}) async {
    if (mode == 'offline') throw const SocketException('offline');
    if (mode == 'conflict' && ifMatchEtag != null) {
      throw CalDavException.fromStatus(412);
    }
    if (ifMatchEtag == null) forcedPuts++;
    return 'etag';
  }

  @override
  Future<void> deleteObject(NextcloudAccount a, String href,
      {String? ifMatchEtag}) async {
    if (mode == 'offline') throw const SocketException('offline');
  }

  @override
  Future<List<CalDavCollection>> listCollections(NextcloudAccount a) async => [];
  @override
  Future<List<CalDavObject>> listObjects(NextcloudAccount a, String h) async =>
      [];
  @override
  Future<String?> fetchCTag(NextcloudAccount a, String h) async => null;

  @override
  Future<List<Principal>> searchPrincipals(NextcloudAccount a, String q)
      async => const [];

  @override
  Future<List<CollectionShare>> listShares(NextcloudAccount a, String hr)
      async => const [];

  @override
  Future<void> setShare(NextcloudAccount a, String hr,
      {required String shareHref, required bool readWrite}) async {}

  @override
  Future<void> removeShare(NextcloudAccount a, String hr,
      {required String shareHref}) async {}
}

void main() {
  final account = const NextcloudAccount(
      baseUrl: 'https://x', username: 'u', appPassword: 'p');

  test('Konflikt beim Abspielen der Queue: Offline-Änderung gewinnt (force)',
      () async {
    final client = _FakeClient();
    final repo = CalDavRepository(client, _FakeCache());

    // 1) Offline eine Änderung einreihen (mit altem ETag).
    client.mode = 'offline';
    await repo.putObject(account, '/c/a.ics', 'ICAL', ifMatchEtag: 'old');
    expect(await repo.pendingCount(account), 1);

    // 2) Online, aber Server hat sich geändert → 412 beim If-Match.
    client.mode = 'conflict';
    await repo.flushQueue(account);

    // Offline-Änderung wurde ohne If-Match erzwungen, Queue ist leer.
    expect(client.forcedPuts, 1);
    expect(await repo.pendingCount(account), 0);
  });

  test('isConflict erkennt HTTP 412', () {
    expect(CalDavException.fromStatus(412).isConflict, isTrue);
    expect(CalDavException.fromStatus(404).isConflict, isFalse);
  });
}
