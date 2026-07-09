import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_item.dart';

/// Pref-Key der gewählten Einkaufsliste (geteilt mit dem Einkaufs-Screen).
const kShoppingListHrefKey = 'shopping_list_href';

/// Ist [list] die Einkaufsliste? (gespeicherte Wahl [prefHref] ODER Name
/// enthält „einkauf"/„shopping").
bool isShoppingList(TaskList list, String? prefHref) {
  if (prefHref != null && prefHref.isNotEmpty && list.href == prefHref) {
    return true;
  }
  final n = list.name.toLowerCase();
  return n.contains('einkauf') || n.contains('shopping');
}

/// Href der als Einkaufsliste gewählten Liste (persistiert), sonst `null`.
final shoppingListHrefProvider =
    AsyncNotifierProvider<ShoppingListHrefController, String?>(
      ShoppingListHrefController.new,
    );

class ShoppingListHrefController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(kShoppingListHrefKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> set(String? href) async {
    final prefs = await SharedPreferences.getInstance();
    if (href == null || href.isEmpty) {
      await prefs.remove(kShoppingListHrefKey);
    } else {
      await prefs.setString(kShoppingListHrefKey, href);
    }
    state = AsyncData(href);
  }
}

/// Flüchtiger Fokus: nur diese Liste (href) im „Liste"-Tab zeigen; `null` = alle.
final focusedTaskListProvider =
    NotifierProvider<FocusedTaskListController, String?>(
      FocusedTaskListController.new,
    );

class FocusedTaskListController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? href) => state = href;
}

/// Erledigte Aufgaben ausblenden?
final hideCompletedProvider =
    AsyncNotifierProvider<HideCompletedController, bool>(
      HideCompletedController.new,
    );

class HideCompletedController extends AsyncNotifier<bool> {
  static const _key = 'tasks_hide_completed';

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> toggle() async {
    final prefs = await SharedPreferences.getInstance();
    final next = !(state.value ?? false);
    await prefs.setBool(_key, next);
    state = AsyncData(next);
  }
}

/// Sortierung: 'manual' (Drag&Drop), 'due' (Fälligkeit) oder 'alpha'.
final taskSortProvider = AsyncNotifierProvider<TaskSortController, String>(
  TaskSortController.new,
);

class TaskSortController extends AsyncNotifier<String> {
  static const _key = 'tasks_sort_mode';

  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? 'manual';
  }

  Future<void> set(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode);
    state = AsyncData(mode);
  }
}
