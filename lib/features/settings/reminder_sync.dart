import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/notifications/notification_service.dart';
import '../calendar/event_providers.dart';
import '../tasks/task_providers.dart';
import 'notification_providers.dart';

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

    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 14));
    final reminders = <ScheduledReminder>[];

    // --- Termine: Vorlaufzeit vor Beginn ---
    final lead = Duration(minutes: settings.leadMinutes);
    final events = ref.read(visibleEventsProvider)
        .where((e) => !e.allDay && e.start.isAfter(now) && e.start.isBefore(horizon))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    var id = 1;
    for (final e in events) {
      final when = e.start.subtract(lead);
      if (!when.isAfter(now)) continue;
      reminders.add(ScheduledReminder(
        id: id++,
        title: e.summary,
        body: 'Beginnt um ${DateFormat('HH:mm').format(e.start)} Uhr'
            '${e.location != null && e.location!.isNotEmpty ? ' · ${e.location}' : ''}',
        when: when,
      ));
      if (id > 60) break;
    }

    // --- Aufgaben: am Fälligkeitstag erinnern ---
    var taskId = 1000;
    final lists = ref.read(tasksControllerProvider).value ?? const [];
    for (final list in lists) {
      for (final t in list.items) {
        if (t.completed || t.due == null) continue;
        final due = t.due!;
        final midnight = due.hour == 0 && due.minute == 0 && due.second == 0;
        final when = midnight
            ? DateTime(due.year, due.month, due.day, 9)
            : due;
        if (!when.isAfter(now) || when.isAfter(horizon)) continue;
        reminders.add(ScheduledReminder(
          id: taskId++,
          title: 'Aufgabe fällig',
          body: t.summary,
          when: when,
        ));
        if (taskId > 1060) break;
      }
    }

    await service.schedule(reminders);
  }
}
