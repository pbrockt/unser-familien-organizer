import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
