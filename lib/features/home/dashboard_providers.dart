import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/account_providers.dart';
import '../calendar/event_providers.dart';
import '../tasks/task_item.dart';
import '../tasks/task_providers.dart';

/// Anzahl offline erzeugter Änderungen, die noch auf Synchronisierung warten.
final pendingSyncCountProvider = FutureProvider.autoDispose<int>((ref) async {
  // Bei Änderungen an Terminen/Aufgaben neu auswerten.
  ref.watch(eventsControllerProvider);
  ref.watch(tasksControllerProvider);
  final account = await ref.watch(accountProvider.future);
  if (account == null) return 0;
  return ref.read(caldavRepositoryProvider).pendingCount(account);
});

/// Anzahl Tage, die unter „Anstehende Termine" vorausgeschaut werden
/// (Standard: 2 = heute + morgen). In den Einstellungen anpassbar.
final upcomingDaysProvider =
    AsyncNotifierProvider<UpcomingDaysController, int>(
        UpcomingDaysController.new);

class UpcomingDaysController extends AsyncNotifier<int> {
  static const _key = 'home_upcoming_days';

  @override
  Future<int> build() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_key) ?? 2;
    return v < 1 ? 1 : v;
  }

  Future<void> set(int days) async {
    final prefs = await SharedPreferences.getInstance();
    final v = days < 1 ? 1 : days;
    await prefs.setInt(_key, v);
    state = AsyncData(v);
  }
}

/// Auf der Startseite gewählter Kalender-Filter (Name eines gespeicherten
/// Presets) oder `null` = „Alle". Wird gerätelokal gespeichert.
final homeCalendarFilterProvider =
    AsyncNotifierProvider<HomeCalendarFilterController, String?>(
        HomeCalendarFilterController.new);

class HomeCalendarFilterController extends AsyncNotifier<String?> {
  static const _key = 'home_calendar_filter';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> set(String? name) async {
    final prefs = await SharedPreferences.getInstance();
    if (name == null || name.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, name);
    }
    state = AsyncData(name);
  }
}

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
