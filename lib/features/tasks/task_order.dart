import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_item.dart';

/// Gerätelokale, manuelle Reihenfolge der Aufgaben je Liste (href → UIDs).
/// Per Drag&Drop kann man wichtige Aufgaben nach oben ziehen.
final taskOrderProvider =
    AsyncNotifierProvider<TaskOrderController, Map<String, List<String>>>(
      TaskOrderController.new,
    );

class TaskOrderController extends AsyncNotifier<Map<String, List<String>>> {
  static const _key = 'task_order';

  @override
  Future<Map<String, List<String>>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(k, (v as List).map((e) => e.toString()).toList()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> setOrder(String listHref, List<String> uids) async {
    final current = Map<String, List<String>>.of(state.value ?? {});
    current[listHref] = uids;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(current));
    state = AsyncData(current);
  }
}

/// Sortiert [items] nach der gespeicherten [order] (UIDs). Nicht enthaltene
/// (neue) Aufgaben behalten ihre ursprüngliche Reihenfolge und landen hinten.
List<TaskItem> applyTaskOrder(List<TaskItem> items, List<String>? order) {
  if (order == null || order.isEmpty) return items;
  final byUid = {for (final t in items) t.uid: t};
  final result = <TaskItem>[];
  for (final uid in order) {
    final t = byUid.remove(uid);
    if (t != null) result.add(t);
  }
  // Übrige (neue) Aufgaben in Originalreihenfolge anhängen.
  for (final t in items) {
    if (byUid.containsKey(t.uid)) result.add(t);
  }
  return result;
}
