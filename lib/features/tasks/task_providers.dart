import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../core/caldav/caldav_repository.dart';
import '../../core/caldav/ical_builder.dart';
import '../../core/caldav/ical_parser.dart';
import '../../shared/utils/hex_color.dart';
import '../members/member_settings.dart';
import 'task_item.dart';

/// Lädt Aufgabenlisten aus der Nextcloud und verwaltet das Abhaken.
final tasksControllerProvider =
    AsyncNotifierProvider<TasksController, List<TaskList>>(
  TasksController.new,
);

class TasksController extends AsyncNotifier<List<TaskList>> {
  static const _parser = IcalParser();
  static const _builder = IcalBuilder();

  bool _disposed = false;

  @override
  Future<List<TaskList>> build() async {
    ref.onDispose(() => _disposed = true);
    final account = await ref.watch(accountProvider.future);
    if (account == null) return const [];
    final repo = ref.watch(caldavRepositoryProvider);
    final settings = ref.watch(memberSettingsProvider).value ?? const {};

    final cached = await repo.cachedSnapshot(account);
    if (cached == null) {
      return _buildLists(await repo.sync(account), settings);
    }
    Future.microtask(() => _backgroundRefresh(account, repo, settings));
    return _buildLists(cached, settings);
  }

  Future<void> _backgroundRefresh(NextcloudAccount account,
      CalDavRepository repo, Map<String, MemberSetting> settings) async {
    try {
      final fresh = await repo.sync(account);
      if (_disposed) return;
      state = AsyncData(_buildLists(fresh, settings));
    } catch (_) {
      // Offline o.ä. → gecachter Stand bleibt sichtbar.
    }
  }

  /// Nach einer Änderung frisch synchronisieren (Delta) und State setzen.
  Future<void> _refresh(NextcloudAccount account) async {
    final repo = ref.read(caldavRepositoryProvider);
    final settings = ref.read(memberSettingsProvider).value ?? const {};
    final fresh = await repo.sync(account);
    if (_disposed) return;
    state = AsyncData(_buildLists(fresh, settings));
  }

  List<TaskList> _buildLists(
      CalDavSnapshot snapshot, Map<String, MemberSetting> settings) {
    final todoCollections =
        snapshot.collections.where((c) => c.supportsTodos);

    final lists = <TaskList>[];
    for (final col in todoCollections) {
      // Mitglieder-Anpassung (eigene Farbe/Name) anwenden.
      final member = settings[col.href];
      final color = parseHexColor(member?.colorHex) ?? parseHexColor(col.color);
      final name = (member?.name != null && member!.name!.isNotEmpty)
          ? member.name!
          : col.displayName;
      final objects = snapshot.objectsOf(col.href);

      final items = <TaskItem>[];
      for (final obj in objects) {
        for (final parsed in _parser.parseTodos(obj.icalData)) {
          items.add(TaskItem.fromParsed(
            parsed,
            objectHref: obj.href,
            etag: obj.etag,
            rawIcal: obj.icalData,
            color: color,
          ));
        }
      }
      _sortItems(items);
      lists.add(TaskList(
        href: col.href,
        name: name,
        color: color,
        items: items,
      ));
    }
    return lists;
  }

  /// Offene zuerst, dann nach Fälligkeit (ohne Datum ans Ende), dann Name.
  void _sortItems(List<TaskItem> items) {
    items.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      final ad = a.due, bd = b.due;
      if (ad != null && bd != null) {
        final c = ad.compareTo(bd);
        if (c != 0) return c;
      } else if (ad != null) {
        return -1;
      } else if (bd != null) {
        return 1;
      }
      return a.summary.toLowerCase().compareTo(b.summary.toLowerCase());
    });
  }

  /// Hakt eine Aufgabe ab bzw. wieder auf – optimistisch im UI, dann per
  /// CalDAV-PUT auf dem Server. Schlägt das fehl, wird zurückgerollt.
  Future<void> toggle(TaskItem item) async {
    final current = state.value;
    if (current == null) return;

    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    final target = !item.completed;

    // 1) Optimistisch umschalten.
    state = AsyncData(_replace(current, item, item.copyWith(completed: target)));

    try {
      final newIcal =
          _parser.toggleTodoCompletion(item.rawIcal, completed: target);
      final newEtag = await repo.putObject(
        account,
        item.objectHref,
        newIcal,
        ifMatchEtag: item.etag.isEmpty ? null : item.etag,
      );
      // 2) Erfolg: rawIcal/ETag im State aktualisieren (offline: ETag bleibt).
      final updated = item.copyWith(
        completed: target,
        rawIcal: newIcal,
        etag: newEtag ?? item.etag,
      );
      final base = state.value ?? current;
      state = AsyncData(_replace(base, item, updated, resort: true));
    } catch (e) {
      // 3) Fehler: zurückrollen und Fehler nach oben geben.
      final base = state.value ?? current;
      state = AsyncData(_replace(base, item, item, resort: true));
      rethrow;
    }
  }

  /// Legt eine neue Aufgabe in der Liste [listHref] an (CalDAV-PUT) und lädt
  /// danach neu.
  Future<void> createTask({
    required String listHref,
    required String summary,
    DateTime? due,
    String? description,
  }) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    final uid = _builder.newUid();
    final ical = _builder.buildTodo(
      uid: uid,
      summary: summary,
      due: due,
      description: description,
    );
    await repo.putObject(account, _objectHref(listHref, uid), ical);
    await _refresh(account);
  }

  /// Aktualisiert Titel/Fälligkeit/Beschreibung einer Aufgabe.
  Future<void> updateTask(
    TaskItem item, {
    required String summary,
    DateTime? due,
    bool clearDue = false,
    String? description,
  }) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    final ical = _builder.updateTodo(
      item.rawIcal,
      summary: summary,
      due: due,
      clearDue: clearDue,
      description: description,
    );
    await repo.putObject(
      account,
      item.objectHref,
      ical,
      ifMatchEtag: item.etag.isEmpty ? null : item.etag,
    );
    await _refresh(account);
  }

  /// Löscht eine Aufgabe (CalDAV-DELETE) und lädt danach neu.
  Future<void> deleteTask(TaskItem item) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    await repo.deleteObject(
      account,
      item.objectHref,
      ifMatchEtag: item.etag.isEmpty ? null : item.etag,
    );
    await _refresh(account);
  }

  /// Löscht alle erledigten Aufgaben einer Liste (z.B. „Erledigte entfernen"
  /// in der Einkaufsliste).
  Future<void> clearCompleted(String listHref) async {
    final lists = state.value;
    if (lists == null) return;
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    final completed = <TaskItem>[];
    for (final list in lists) {
      if (list.href != listHref) continue;
      completed.addAll(list.items.where((t) => t.completed));
    }
    if (completed.isEmpty) return;

    for (final item in completed) {
      await repo.deleteObject(
        account,
        item.objectHref,
        ifMatchEtag: item.etag.isEmpty ? null : item.etag,
      );
    }
    await _refresh(account);
  }

  /// Ziel-URL eines neuen Objekts: `<collection>/<uid>.ics`.
  String _objectHref(String listHref, String uid) {
    final base = listHref.endsWith('/') ? listHref : '$listHref/';
    return '$base$uid.ics';
  }

  /// Ersetzt [oldItem] (per uid + objectHref) durch [newItem] in den Listen.
  List<TaskList> _replace(
    List<TaskList> lists,
    TaskItem oldItem,
    TaskItem newItem, {
    bool resort = false,
  }) {
    return lists.map((list) {
      var changed = false;
      final items = list.items.map((t) {
        if (t.uid == oldItem.uid && t.objectHref == oldItem.objectHref) {
          changed = true;
          return newItem;
        }
        return t;
      }).toList();
      if (changed && resort) _sortItems(items);
      return changed ? list.withItems(items) : list;
    }).toList();
  }
}
