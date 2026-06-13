import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../calendar/event_providers.dart';
import '../tasks/task_providers.dart';
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
    return child;
  }

  Future<void> _reschedule(WidgetRef ref) async {
    final settings = ref.read(notificationSettingsProvider).value;
    final service = ref.read(notificationServiceProvider);
    if (settings == null) return;

    if (!settings.enabled) {
      await service.cancelAll();
      return;
    }
    if (!await service.areNotificationsEnabled()) return;

    final reminders = planReminders(
      events: ref.read(visibleEventsProvider),
      taskLists: ref.read(tasksControllerProvider).value ?? const [],
      leadMinutes: settings.leadMinutes,
    );
    await service.schedule(reminders);
  }
}
