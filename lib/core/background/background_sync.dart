import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../../features/calendar/events_builder.dart';
import '../../features/fitness/fitness_overrides.dart';
import '../../features/fitness/fitness_providers.dart';
import '../../features/fitness/fitness_repository.dart';
import '../../features/fitness/fitness_settings.dart';
import '../../features/fitness/health_connect_mapping.dart';
import '../../features/fitness/weekly_report.dart';
import '../../features/nutrition/nutrition_repository.dart';
import '../../features/fitness/health_connect_sync.dart';
import '../../features/nutrition/nutrition_refresh.dart';
import '../../features/members/member_settings.dart';
import '../../features/settings/backup_providers.dart';
import '../../features/settings/briefing_planner.dart';
import '../../features/settings/briefing_providers.dart';
import '../../features/settings/notification_providers.dart';
import '../../features/settings/reminder_planner.dart';
import '../notifications/notification_service.dart';
import '../../features/tasks/tasks_builder.dart';
import '../../features/weather/weather_service.dart';
import '../auth/account_providers.dart';
import '../backup/backup_service.dart';
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

      // Gesundheitsdaten aus Health Connect in die Nextcloud — nur wenn eingeschaltet,
      // höchstens alle 30 Minuten. Vor dem Kalender, damit ein Fehler dort sie nicht
      // aufhält.
      try {
        final ordner = await container.read(fitnessFolderProvider.future);
        await HealthConnectSync().runIfDue(account: account, fitnessFolder: ordner);
      } catch (_) {}

      // Einmal pro Woche „Meine Lebensmittel" bei Open Food Facts auffrischen.
      try {
        final ordner = await container.read(fitnessFolderProvider.future);
        await NutritionWeeklyRefresh().runIfDue(account: account, fitnessFolder: ordner);
      } catch (_) {}

      // Frisch synchronisieren (Delta). Schlägt das Netz fehl, mit dem
      // gecachten Stand weitermachen, damit das Widget trotzdem aktualisiert.
      final repo = container.read(caldavRepositoryProvider);
      final snapshot = await () async {
        try {
          return await repo.sync(account);
        } catch (_) {
          return await repo.cachedSnapshot(account);
        }
      }();
      if (snapshot == null) return true;
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

      // Erinnerungen (falls aktiviert) + tägliches Briefing (falls aktiviert).
      final settings = await container.read(
        notificationSettingsProvider.future,
      );
      final briefingCfg = await container.read(briefingSettingsProvider.future);
      final service = container.read(notificationServiceProvider);
      if (await service.areNotificationsEnabled()) {
        final items = <ScheduledReminder>[];
        if (settings.enabled) {
          items.addAll(planReminders(events: events, taskLists: lists));
        }
        final briefing = planDailyBriefing(
          events: events,
          taskLists: lists,
          weather: weather,
          enabled: briefingCfg.enabled,
          minutesOfDay: briefingCfg.minutesOfDay,
        );
        if (briefing != null) items.add(briefing);
        // Wochenbericht: Auch er muss hier mit in die Liste, sonst nähme ihn das
        // Neuplanen (das zuerst alles löscht) wieder heraus.
        try {
          final bericht = await _wochenbericht(container);
          if (bericht != null) items.add(bericht);
        } catch (_) {}
        await service.schedule(items);
      }

      // Automatische Sicherung (falls fällig).
      try {
        final prefs = await SharedPreferences.getInstance();
        final freq = prefs.getString(kBackupFreqKey) ?? 'weekly';
        final lastMs = prefs.getInt(kBackupLastKey);
        final last = lastMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastMs);
        if (isBackupDue(freq, last, DateTime.now())) {
          final svc = BackupService(account);
          await svc.createBackup();
          await svc.pruneOld();
          await prefs.setInt(
            kBackupLastKey,
            DateTime.now().millisecondsSinceEpoch,
          );
        }
      } catch (_) {}
      return true;
    } catch (_) {
      return false; // WorkManager versucht es später erneut.
    } finally {
      container.dispose();
    }
  });
}

/// Liest für den Wochenbericht die lokalen Zwischenstände direkt — die Provider würden
/// hier jedes Mal einen vollständigen Abgleich anstoßen.
Future<ScheduledReminder?> _wochenbericht(ProviderContainer container) async {
  final an = await container.read(fitnessEnabledProvider.future) &&
      await container.read(fitnessWeeklyReportProvider.future);
  if (!an) return null;
  final fitness = await FitnessRepository().load();
  final ernaehrung = await NutritionRepository().load();
  final overrides = await container.read(fitnessOverridesProvider.future);
  final manuell = await container.read(weightEntriesProvider.future);
  return planWeeklyReport(
    enabled: true,
    // Wie in der App: entfernte Einheiten weg, doppelte nur einmal.
    activities: withoutHcDuplicates([
      for (final a in fitness.activities)
        if (!overrides.hidden.contains(a.id)) a,
    ]),
    sportOf: (a) => overrides.sports[a.id] ?? a.sportEffective,
    healthDays: fitness.healthDays,
    nutrition: ernaehrung.days,
    weights: mergeWeights(manuell, fitness.healthDays),
  );
}

/// Initialisiert WorkManager (in main aufrufen). Nur Android.
Future<void> initBackgroundSync() async {
  if (!isAndroid) return;
  await Workmanager().initialize(callbackDispatcher);
}

/// Plant den periodischen Hintergrund-Sync (alle 15 Min, auch ohne Netz).
/// Aktualisiert die Home-Widgets und plant – falls aktiv – Erinnerungen neu.
Future<void> registerBackgroundSync() async {
  if (!isAndroid) return;
  await Workmanager().registerPeriodicTask(
    _uniqueName,
    _taskName,
    // Alle 15 Minuten (Android-Minimum) und auch ohne Netz laufen, damit die
    // Home-Widgets zuverlässig aktualisiert werden (Sync fällt sonst auf den
    // Cache zurück).
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.notRequired),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
  );
}

/// Stoppt den periodischen Hintergrund-Sync.
Future<void> cancelBackgroundSync() async {
  if (!isAndroid) return;
  await Workmanager().cancelByUniqueName(_uniqueName);
}
