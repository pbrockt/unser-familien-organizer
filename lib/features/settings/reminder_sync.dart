import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/home_widgets.dart';
import '../calendar/event_providers.dart';
import '../members/member_settings.dart';
import '../tasks/task_providers.dart';
import '../weather/weather_service.dart';
import 'notification_providers.dart';
import 'reminder_planner.dart';

/// Hört auf Termine, Aufgaben und Einstellungen und plant lokale Erinnerungen
/// (für anstehende Termine und fällige Aufgaben). Wird um die App gelegt.
class ReminderSync extends ConsumerWidget {
  const ReminderSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(eventsControllerProvider, (_, _) => _reschedule(ref));
    ref.listen(tasksControllerProvider, (_, _) => _reschedule(ref));
    ref.listen(notificationSettingsProvider, (_, _) => _reschedule(ref));
    ref.listen(memberSettingsProvider, (_, _) => _reschedule(ref));
    ref.listen(weatherProvider, (_, _) => _reschedule(ref));
    return child;
  }

  Future<void> _reschedule(WidgetRef ref) async {
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
    final service = ref.read(notificationServiceProvider);
    if (settings == null) return;

    if (!settings.enabled) {
      await service.cancelAll();
      return;
    }
    if (!await service.areNotificationsEnabled()) return;

    final reminders = planReminders(
      events: events,
      taskLists: lists,
      leadMinutes: settings.leadMinutes,
    );
    await service.schedule(reminders);
  }
}
