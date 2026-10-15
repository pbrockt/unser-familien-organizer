import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/widgets/home_widgets.dart';
import '../fitness/fitness_overrides.dart';
import '../fitness/fitness_providers.dart';
import '../fitness/fitness_settings.dart';
import '../fitness/fitness_widget_data.dart';
import '../fitness/weekly_report.dart';
import '../nutrition/nutrition_providers.dart';
import '../calendar/event_providers.dart';
import '../members/member_settings.dart';
import '../tasks/task_providers.dart';
import '../weather/weather_service.dart';
import 'briefing_planner.dart';
import 'briefing_providers.dart';
import 'notification_providers.dart';
import 'reminder_planner.dart';

/// Hört auf Termine, Aufgaben und Einstellungen und plant lokale Erinnerungen
/// (für anstehende Termine und fällige Aufgaben). Aktualisiert außerdem die
/// Home-Screen-Widgets – beim Start, bei Datenänderungen und immer dann, wenn
/// die App wieder in den Vordergrund kommt. Wird um die App gelegt.
class ReminderSync extends ConsumerStatefulWidget {
  const ReminderSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReminderSync> createState() => _ReminderSyncState();
}

class _ReminderSyncState extends ConsumerState<ReminderSync>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Direkt nach dem ersten Frame die Widgets befüllen, damit sie nach einem
    // App-Update nicht auf dem System-Platzhalter hängen bleiben.
    WidgetsBinding.instance.addPostFrameCallback((_) => _reschedule());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Bei Rückkehr in die App die Widgets erneut aktualisieren.
    if (state == AppLifecycleState.resumed) _reschedule();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(eventsControllerProvider, (_, _) => _reschedule());
    ref.listen(tasksControllerProvider, (_, _) => _reschedule());
    ref.listen(notificationSettingsProvider, (_, _) => _reschedule());
    ref.listen(briefingSettingsProvider, (_, _) => _reschedule());
    ref.listen(memberSettingsProvider, (_, _) => _reschedule());
    ref.listen(weatherProvider, (_, _) => _reschedule());
    ref.listen(fitnessDataProvider, (_, _) => _reschedule());
    ref.listen(nutritionProvider, (_, _) => _reschedule());
    ref.listen(fitnessWeeklyReportProvider, (_, _) => _reschedule());
    return widget.child;
  }

  /// Inhalt fürs Fitness-Widget — null, solange der Bereich aus ist oder nichts
  /// eingelesen wurde. Dann bleibt das Widget bei seinem Platzhalter, statt eine
  /// leere Woche zu behaupten.
  FitnessWidgetData? _fitnessData() {
    final an = ref.read(fitnessEnabledProvider).value ?? false;
    if (!an) return null;
    final daten = ref.read(fitnessDataProvider).value;
    if (daten == null || daten.activities.isEmpty) return null;

    final overrides = ref.read(fitnessOverridesProvider).value;
    final ernaehrung = ref.read(nutritionProvider).value;
    final heute = DateTime.now();
    final key = '${heute.year.toString().padLeft(4, '0')}-'
        '${heute.month.toString().padLeft(2, '0')}-${heute.day.toString().padLeft(2, '0')}';
    // Nur wer das Tagebuch benutzt, bekommt die Kalorienzeile.
    final nutzt = ernaehrung?.days.values.any((d) => d.entries.isNotEmpty) ?? false;
    return buildFitnessWidgetData(
      activities: daten.activities,
      sportOf: (a) => overrides?.sports[a.id] ?? a.sportEffective,
      healthDays: daten.healthDays,
      stepGoal: ref.read(fitnessStepGoalProvider).value ?? 8000,
      today: heute,
      kcalEaten: nutzt ? ernaehrung!.day(key).kcal.round() : null,
      kcalGoal: ref.read(fitnessKcalGoalProvider).value ?? 2000,
    );
  }

  Future<void> _reschedule() async {
    final events = ref.read(visibleEventsProvider);
    final lists = ref.read(tasksControllerProvider).value ?? const [];
    final memberSettings = ref.read(memberSettingsProvider).value ?? const {};
    final weather = ref.read(weatherProvider).value ?? const {};

    // Home-Screen-Widgets immer aktualisieren (unabhängig von Erinnerungen).
    await HomeWidgets.update(
      events: events,
      lists: lists,
      memberSettings: memberSettings,
      weather: weather,
      fitness: _fitnessData(),
    );

    final settings = ref.read(notificationSettingsProvider).value;
    final briefingCfg =
        ref.read(briefingSettingsProvider).value ?? const BriefingSettings();
    final service = ref.read(notificationServiceProvider);
    if (settings == null) return;
    if (!await service.areNotificationsEnabled()) {
      if (!settings.enabled) await service.cancelAll();
      return;
    }

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
    final bericht = _wochenbericht();
    if (bericht != null) items.add(bericht);
    await service.schedule(items);
  }

  ScheduledReminder? _wochenbericht() {
    final an = (ref.read(fitnessEnabledProvider).value ?? false) &&
        (ref.read(fitnessWeeklyReportProvider).value ?? true);
    final daten = ref.read(fitnessDataProvider).value;
    final overrides = ref.read(fitnessOverridesProvider).value;
    return planWeeklyReport(
      enabled: an,
      activities: daten?.activities ?? const [],
      sportOf: (a) => overrides?.sports[a.id] ?? a.sportEffective,
      healthDays: daten?.healthDays ?? const [],
      nutrition: ref.read(nutritionProvider).value?.days ?? const {},
      weights: ref.read(mergedWeightProvider),
    );
  }
}
