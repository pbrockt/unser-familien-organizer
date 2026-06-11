import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/notifications/notification_service.dart';
import '../calendar/calendar_event.dart';
import '../calendar/event_providers.dart';
import 'notification_providers.dart';

/// Hört auf Termine + Einstellungen und plant lokale Erinnerungen.
/// Wird um die App gelegt; aktiviert dadurch auch das Laden der Termine.
class ReminderSync extends ConsumerWidget {
  const ReminderSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Neu planen, wenn sich Termine ändern …
    ref.listen<AsyncValue<List<CalendarEvent>>>(eventsControllerProvider,
        (prev, next) {
      final events = next.value;
      if (events != null) _reschedule(ref, events);
    });
    // … oder die Einstellungen.
    ref.listen(notificationSettingsProvider, (prev, next) {
      final events = ref.read(eventsControllerProvider).value;
      if (events != null) _reschedule(ref, events);
    });
    return child;
  }

  Future<void> _reschedule(WidgetRef ref, List<CalendarEvent> events) async {
    final settings = ref.read(notificationSettingsProvider).value;
    final service = ref.read(notificationServiceProvider);
    if (settings == null) return;

    if (!settings.enabled) {
      await service.cancelAll();
      return;
    }
    if (!await service.areNotificationsEnabled()) return;

    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 7));
    final lead = Duration(minutes: settings.leadMinutes);

    final upcoming = events
        .where((e) =>
            !e.allDay && e.start.isAfter(now) && e.start.isBefore(horizon))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final reminders = <ScheduledReminder>[];
    var id = 1;
    for (final e in upcoming) {
      final when = e.start.subtract(lead);
      if (!when.isAfter(now)) continue;
      reminders.add(ScheduledReminder(
        id: id++,
        title: e.summary,
        body: 'Beginnt um ${DateFormat('HH:mm').format(e.start)} Uhr'
            '${e.location != null && e.location!.isNotEmpty ? ' · ${e.location}' : ''}',
        when: when,
      ));
      if (id > 60) break; // Plattform-Limit schonen.
    }
    await service.schedule(reminders);
  }
}
