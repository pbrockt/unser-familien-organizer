import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/caldav/ical_parser.dart';
import '../../shared/utils/hex_color.dart';
import 'calendar_event.dart';

/// Lädt alle Termine aus allen Kalender-Collections der verbundenen Nextcloud
/// und parst sie zu [CalendarEvent]s.
///
/// Hinweis (Phase 2): Serientermine (RRULE) werden aktuell nur als ihre
/// Basis-Instanz angezeigt; die volle RRULE-Expansion folgt.
final eventsProvider =
    FutureProvider.autoDispose<List<CalendarEvent>>((ref) async {
  final account = await ref.watch(accountProvider.future);
  if (account == null) return const [];

  final client = ref.watch(caldavClientProvider);
  const parser = IcalParser();

  final collections = await client.listCollections(account);
  final eventCollections = collections.where((c) => c.supportsEvents);

  final events = <CalendarEvent>[];
  for (final col in eventCollections) {
    final color = parseHexColor(col.color);
    final objects = await client.listObjects(account, col.href);
    for (final obj in objects) {
      for (final parsed in parser.parseEvents(obj.icalData)) {
        events.add(CalendarEvent.fromParsed(
          parsed,
          color: color,
          calendarName: col.displayName,
        ));
      }
    }
  }

  events.sort((a, b) => a.start.compareTo(b.start));
  return events;
});

/// Termine gruppiert nach Tag – praktisch als `eventLoader` für table_calendar.
final eventsByDayProvider =
    Provider.autoDispose<Map<DateTime, List<CalendarEvent>>>((ref) {
  final asyncEvents = ref.watch(eventsProvider);
  final map = <DateTime, List<CalendarEvent>>{};
  for (final e in asyncEvents.value ?? const []) {
    map.putIfAbsent(e.startDay, () => []).add(e);
  }
  return map;
});
