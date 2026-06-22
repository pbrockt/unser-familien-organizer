import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/widgets/home_widgets.dart';
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
    return widget.child;
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
    await service.schedule(items);
  }
}
