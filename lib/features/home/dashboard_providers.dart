import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tasks/task_item.dart';
import '../tasks/task_providers.dart';

/// Kurz-Zusammenfassung der Einkaufsliste fürs Dashboard.
typedef ShoppingSummary = ({String? listName, int openCount});

/// Ermittelt die gewählte Einkaufsliste (gleiche Logik wie der Einkauf-Tab)
/// und ihre Anzahl offener Artikel.
final shoppingSummaryProvider =
    FutureProvider.autoDispose<ShoppingSummary>((ref) async {
  final lists = ref.watch(tasksControllerProvider).value ?? const <TaskList>[];
  if (lists.isEmpty) return (listName: null, openCount: 0);

  final prefs = await SharedPreferences.getInstance();
  final href = prefs.getString('shopping_list_href');

  TaskList? selected;
  if (href != null) {
    for (final l in lists) {
      if (l.href == href) {
        selected = l;
        break;
      }
    }
  }
  if (selected == null) {
    for (final l in lists) {
      final n = l.name.toLowerCase();
      if (n.contains('einkauf') || n.contains('shopping')) {
        selected = l;
        break;
      }
    }
  }
  selected ??= lists.first;

  return (listName: selected.name, openCount: selected.openCount);
});
