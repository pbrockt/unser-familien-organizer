import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/calendar/events_builder.dart';
import '../../features/members/member_settings.dart';
import '../../features/settings/notification_providers.dart';
import '../../features/settings/reminder_planner.dart';
import '../../features/tasks/tasks_builder.dart';
import '../../features/weather/weather_service.dart';
import '../auth/account_providers.dart';
import '../platform/platform_support.dart';
import '../widgets/home_widgets.dart';

const _uniqueName = 'familyplanner-sync';
const _taskName = 'familyplanner-periodic-sync';

/// Einstiegspunkt des Hintergrund-Isolates (von WorkManager aufgerufen).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final container = ProviderContainer();
    try {
      final account = await container.read(accountProvider.future);
      if (account == null) return true;

      // Frisch synchronisieren (Delta).
      final repo = container.read(caldavRepositoryProvider);
      final snapshot = await repo.sync(account);
      final memberSettings = await container.read(
        memberSettingsProvider.future,
      );

      final events = filterVisibleEvents(
        buildEventsFromSnapshot(snapshot),
        memberSettings,
      );
      final lists = buildTaskListsFromSnapshot(snapshot, memberSettings);

      // Wetter (falls PLZ gesetzt) für das Überblick-Widget; Fehler ignorieren.
      Map<String, DayWeather> weather = const {};
      try {
        weather = await container.read(weatherProvider.future);
      } catch (_) {}

      // Home-Screen-Widgets immer aktualisieren.
      await HomeWidgets.update(
        events: events,
        lists: lists,
        memberSettings: memberSettings,
        weather: weather,
      );

      // Erinnerungen nur, wenn aktiviert.
      final settings = await container.read(
        notificationSettingsProvider.future,
      );
      final service = container.read(notificationServiceProvider);
      if (settings.enabled && await service.areNotificationsEnabled()) {
        await service.schedule(planReminders(events: events, taskLists: lists));
      }
      return true;
    } catch (_) {
      return false; // WorkManager versucht es später erneut.
    } finally {
      container.dispose();
    }
  });
}

/// Initialisiert WorkManager (in main aufrufen). Nur Android.
Future<void> initBackgroundSync() async {
  if (!isAndroid) return;
  await Workmanager().initialize(callbackDispatcher);
}

/// Plant den periodischen Hintergrund-Sync (etwa stündlich, nur mit Netz).
/// Aktualisiert die Home-Widgets und plant – falls aktiv – Erinnerungen neu.
Future<void> registerBackgroundSync() async {
  if (!isAndroid) return;
  await Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    frequency: const Duration(hours: 1),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// Stoppt den periodischen Hintergrund-Sync.
Future<void> cancelBackgroundSync() async {
  if (!isAndroid) return;
  await Workmanager().cancelByUniqueName(_uniqueName);
}
