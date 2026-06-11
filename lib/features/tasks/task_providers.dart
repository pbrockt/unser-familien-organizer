import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/caldav/ical_builder.dart';
import '../../core/caldav/ical_parser.dart';
import '../../shared/utils/hex_color.dart';
import 'task_item.dart';

/// Lädt Aufgabenlisten aus der Nextcloud und verwaltet das Abhaken.
final tasksControllerProvider =
    AsyncNotifierProvider<TasksController, List<TaskList>>(
  TasksController.new,
);

class TasksController extends AsyncNotifier<List<TaskList>> {
  static const _parser = IcalParser();
  static const _builder = IcalBuilder();

  @override
  Future<List<TaskList>> build() async {
    final account = await ref.watch(accountProvider.future);
    if (account == null) return const [];

    final client = ref.watch(caldavClientProvider);
    final collections = await client.listCollections(account);
    final todoCollections = collections.where((c) => c.supportsTodos);

    final lists = <TaskList>[];
    for (final col in todoCollections) {
      final color = parseHexColor(col.color);
      final objects = await client.listObjects(account, col.href);

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
        name: col.displayName,
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
    final client = ref.read(caldavClientProvider);

    final target = !item.completed;

    // 1) Optimistisch umschalten.
    state = AsyncData(_replace(current, item, item.copyWith(completed: target)));

    try {
      final newIcal =
          _parser.toggleTodoCompletion(item.rawIcal, completed: target);
      final newEtag = await client.putObject(
        account,
        item.objectHref,
        newIcal,
        ifMatchEtag: item.etag.isEmpty ? null : item.etag,
      );
      // 2) Erfolg: rawIcal/ETag im State aktualisieren.
      final updated = item.copyWith(
        completed: target,
        rawIcal: newIcal,
        etag: newEtag,
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
    final client = ref.read(caldavClientProvider);

    final uid = _builder.newUid();
    final ical = _builder.buildTodo(
      uid: uid,
      summary: summary,
      due: due,
      description: description,
    );
    await client.putObject(account, _objectHref(listHref, uid), ical);
    ref.invalidateSelf();
    await future;
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
    final client = ref.read(caldavClientProvider);

    final ical = _builder.updateTodo(
      item.rawIcal,
      summary: summary,
      due: due,
      clearDue: clearDue,
      description: description,
    );
    await client.putObject(
      account,
      item.objectHref,
      ical,
      ifMatchEtag: item.etag.isEmpty ? null : item.etag,
    );
    ref.invalidateSelf();
    await future;
  }

  /// Löscht eine Aufgabe (CalDAV-DELETE) und lädt danach neu.
  Future<void> deleteTask(TaskItem item) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final client = ref.read(caldavClientProvider);

    await client.deleteObject(
      account,
      item.objectHref,
      ifMatchEtag: item.etag.isEmpty ? null : item.etag,
    );
    ref.invalidateSelf();
    await future;
  }

  /// Löscht alle erledigten Aufgaben einer Liste (z.B. „Erledigte entfernen"
  /// in der Einkaufsliste).
  Future<void> clearCompleted(String listHref) async {
    final lists = state.value;
    if (lists == null) return;
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final client = ref.read(caldavClientProvider);

    final completed = <TaskItem>[];
    for (final list in lists) {
      if (list.href != listHref) continue;
      completed.addAll(list.items.where((t) => t.completed));
    }
    if (completed.isEmpty) return;

    for (final item in completed) {
      await client.deleteObject(
        account,
        item.objectHref,
        ifMatchEtag: item.etag.isEmpty ? null : item.etag,
      );
    }
    ref.invalidateSelf();
    await future;
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
