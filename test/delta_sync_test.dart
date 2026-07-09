import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/auth/nextcloud_account.dart';
import 'package:family_planner/core/cache/caldav_cache.dart';
import 'package:family_planner/core/caldav/caldav_client.dart';
import 'package:family_planner/core/caldav/caldav_repository.dart';
import 'package:family_planner/core/caldav/caldav_sharing.dart';

/// In-Memory-Cache (überschreibt alle genutzten Methoden, keine SQLite).
class _FakeCache extends CalDavCache {
  CachedSnapshot? snap;

  @override
  Future<CachedSnapshot?> load(String account) async => snap;
  @override
  Future<void> save(String account, CachedSnapshot s) async => snap = s;
  @override
  Future<List<PendingOp>> pendingOps(String account) async => [];
  @override
  Future<int> pendingCount(String account) async => 0;
  @override
  Future<void> addPendingOp(
    String account, {
    required String kind,
    required String objectHref,
    String? icalData,
    String? ifMatchEtag,
  }) async {}
  @override
  Future<void> removePendingOp(int id) async {}
  @override
  Future<void> upsertObject(
    String account,
    String collectionHref,
    CalDavObject object,
  ) async {}
  @override
  Future<void> removeObject(String account, String objectHref) async {}
}

class _FakeClient implements CalDavClient {
  _FakeClient(this.collections);
  List<CalDavCollection> collections;
  int listObjectsCalls = 0;

  @override
  Future<List<CalDavCollection>> listCollections(NextcloudAccount a) async =>
      collections;

  @override
  Future<List<CalDavObject>> listObjects(
    NextcloudAccount a,
    String href,
  ) async {
    listObjectsCalls++;
    return [CalDavObject(href: '${href}o.ics', etag: 'e', icalData: 'X')];
  }

  @override
  Future<String> putObject(
    NextcloudAccount a,
    String href,
    String ical, {
    String? ifMatchEtag,
  }) async => 'e';
  @override
  Future<void> deleteObject(
    NextcloudAccount a,
    String href, {
    String? ifMatchEtag,
  }) async {}
  @override
  Future<String?> fetchCTag(NextcloudAccount a, String href) async => null;

  @override
  Future<List<Principal>> searchPrincipals(
    NextcloudAccount a,
    String q,
  ) async => const [];

  @override
  Future<List<String>> fetchUserGroups(NextcloudAccount a) async => const [];

  @override
  Future<List<CollectionShare>> listShares(
    NextcloudAccount a,
    String h,
  ) async => const [];

  @override
  Future<void> setShare(
    NextcloudAccount a,
    String h, {
    required String shareHref,
    required bool readWrite,
  }) async {}

  @override
  Future<void> removeShare(
    NextcloudAccount a,
    String h, {
    required String shareHref,
  }) async {}

  @override
  Future<void> createCalendar(
    NextcloudAccount a, {
    required String displayName,
    required bool events,
    required bool todos,
    String? color,
  }) async {}

  @override
  Future<void> renameCalendar(
    NextcloudAccount a,
    String h,
    String name,
  ) async {}

  @override
  Future<void> deleteCalendar(NextcloudAccount a, String h) async {}
}

void main() {
  final account = const NextcloudAccount(
    baseUrl: 'https://x',
    username: 'u',
    appPassword: 'p',
  );

  test('Delta-Sync: unveränderte Collection (gleiches CTag) wird nicht neu '
      'geladen', () async {
    final client = _FakeClient([
      const CalDavCollection(
        href: '/c1/',
        displayName: 'C1',
        ctag: 'A',
        supportsEvents: true,
      ),
    ]);
    final repo = CalDavRepository(client, _FakeCache());

    await repo.sync(account);
    expect(client.listObjectsCalls, 1);

    await repo.sync(account); // CTag unverändert
    expect(client.listObjectsCalls, 1, reason: 'kein erneuter Download');

    client.collections = [
      const CalDavCollection(
        href: '/c1/',
        displayName: 'C1',
        ctag: 'B',
        supportsEvents: true,
      ),
    ];
    await repo.sync(account); // CTag geändert
    expect(client.listObjectsCalls, 2, reason: 'jetzt neu geladen');
  });

  test('cachedSnapshot liefert sofort den gespeicherten Stand', () async {
    final client = _FakeClient([
      const CalDavCollection(
        href: '/c1/',
        displayName: 'C1',
        ctag: 'A',
        supportsEvents: true,
      ),
    ]);
    final repo = CalDavRepository(client, _FakeCache());

    expect(await repo.cachedSnapshot(account), isNull);
    await repo.sync(account);
    final cached = await repo.cachedSnapshot(account);
    expect(cached, isNotNull);
    expect(cached!.collections, hasLength(1));
    expect(cached.fromCache, isTrue);
  });
}
