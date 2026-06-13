import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/calendar/events_builder.dart';
import '../../features/members/member_settings.dart';
import '../../features/settings/notification_providers.dart';
import '../../features/settings/reminder_planner.dart';
import '../../features/tasks/tasks_builder.dart';
import '../auth/account_providers.dart';

const _uniqueName = 'familyplanner-sync';
const _taskName = 'familyplanner-periodic-sync';

/// Einstiegspunkt des Hintergrund-Isolates (von WorkManager aufgerufen).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    final container = ProviderContainer();
    try {
      final settings =
          await container.read(notificationSettingsProvider.future);
      if (!settings.enabled) return true;

      final service = container.read(notificationServiceProvider);
      if (!await service.areNotificationsEnabled()) return true;

      final account = await container.read(accountProvider.future);
      if (account == null) return true;

      // Frisch synchronisieren (Delta) und Erinnerungen neu planen.
      final repo = container.read(caldavRepositoryProvider);
      final snapshot = await repo.sync(account);
      final memberSettings =
          await container.read(memberSettingsProvider.future);

      final events = filterVisibleEvents(
          buildEventsFromSnapshot(snapshot), memberSettings);
      final lists = buildTaskListsFromSnapshot(snapshot, memberSettings);
      final reminders = planReminders(
        events: events,
        taskLists: lists,
        leadMinutes: settings.leadMinutes,
      );
      await service.schedule(reminders);
      return true;
    } catch (_) {
      return false; // WorkManager versucht es später erneut.
    } finally {
      container.dispose();
    }
  });
}

/// Initialisiert WorkManager (in main aufrufen).
Future<void> initBackgroundSync() =>
    Workmanager().initialize(callbackDispatcher);

/// Plant den periodischen Hintergrund-Sync (alle ~2 Stunden, nur mit Netz).
Future<void> registerBackgroundSync() => Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: const Duration(hours: 2),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );

/// Stoppt den periodischen Hintergrund-Sync.
Future<void> cancelBackgroundSync() =>
    Workmanager().cancelByUniqueName(_uniqueName);
