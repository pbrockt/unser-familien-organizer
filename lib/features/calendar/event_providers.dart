import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/caldav/ical_builder.dart';
import '../../core/caldav/ical_parser.dart';
import '../../core/caldav/recurrence_expander.dart';
import '../../shared/utils/hex_color.dart';
import 'calendar_event.dart';

/// Lädt alle Termine aus den Kalender-Collections der Nextcloud und verwaltet
/// Anlegen/Bearbeiten/Löschen.
///
/// Hinweis (Phase 2): Serientermine (RRULE) werden aktuell nur als ihre
/// Basis-Instanz angezeigt; die volle RRULE-Expansion folgt.
final eventsControllerProvider =
    AsyncNotifierProvider<EventsController, List<CalendarEvent>>(
  EventsController.new,
);

class EventsController extends AsyncNotifier<List<CalendarEvent>> {
  static const _parser = IcalParser();
  static const _builder = IcalBuilder();
  static const _expander = RecurrenceExpander();

  @override
  Future<List<CalendarEvent>> build() async {
    final account = await ref.watch(accountProvider.future);
    if (account == null) return const [];

    final snapshot = await ref.watch(caldavRepositoryProvider).load(account);
    final eventCollections =
        snapshot.collections.where((c) => c.supportsEvents);

    // Expansions-Fenster für Serientermine: ~2 Monate zurück bis ~14 voraus.
    final today = DateTime.now();
    final windowStart =
        DateTime(today.year, today.month, today.day).subtract(
      const Duration(days: 60),
    );
    final windowEnd = windowStart.add(const Duration(days: 485));

    final events = <CalendarEvent>[];
    for (final col in eventCollections) {
      final color = parseHexColor(col.color);
      final objects = snapshot.objectsOf(col.href);
      for (final obj in objects) {
        for (final parsed in _parser.parseEvents(obj.icalData)) {
          final base = CalendarEvent.fromParsed(
            parsed,
            color: color,
            calendarName: col.displayName,
            calendarHref: col.href,
            objectHref: obj.href,
            etag: obj.etag,
            rawIcal: obj.icalData,
          );
          final rule = parsed.recurrence;
          if (rule == null) {
            events.add(base);
            continue;
          }
          // Serientermin: in einzelne Instanzen im Fenster expandieren.
          final duration = parsed.end?.difference(parsed.start);
          final occurrences = _expander.expand(
            parsed.start,
            rule,
            windowStart: windowStart,
            windowEnd: windowEnd,
          );
          if (occurrences.isEmpty) {
            events.add(base); // Fallback: wenigstens die Basis zeigen.
            continue;
          }
          for (final occ in occurrences) {
            events.add(_occurrence(base, occ, duration));
          }
        }
      }
    }
    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  /// Erzeugt eine Serien-Instanz aus dem Basistermin mit verschobenem Start.
  CalendarEvent _occurrence(
      CalendarEvent base, DateTime start, Duration? duration) {
    return CalendarEvent(
      uid: base.uid,
      summary: base.summary,
      start: start,
      end: duration == null ? null : start.add(duration),
      description: base.description,
      location: base.location,
      allDay: base.allDay,
      isRecurring: true,
      color: base.color,
      calendarName: base.calendarName,
      calendarHref: base.calendarHref,
      objectHref: base.objectHref,
      etag: base.etag,
      rawIcal: base.rawIcal,
    );
  }

  Future<void> createEvent({
    required String calendarHref,
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
  }) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final client = ref.read(caldavClientProvider);

    final uid = _builder.newUid();
    final ical = _builder.buildEvent(
      uid: uid,
      summary: summary,
      start: start,
      end: end,
      allDay: allDay,
      description: description,
      location: location,
    );
    await client.putObject(account, _objectHref(calendarHref, uid), ical);
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateEvent(
    CalendarEvent event, {
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
  }) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final client = ref.read(caldavClientProvider);

    final ical = _builder.updateEvent(
      event.rawIcal,
      summary: summary,
      start: start,
      end: end,
      allDay: allDay,
      description: description,
      location: location,
    );
    await client.putObject(
      account,
      event.objectHref,
      ical,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
    );
    ref.invalidateSelf();
    await future;
  }

  Future<void> deleteEvent(CalendarEvent event) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final client = ref.read(caldavClientProvider);

    await client.deleteObject(
      account,
      event.objectHref,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
    );
    ref.invalidateSelf();
    await future;
  }

  String _objectHref(String collectionHref, String uid) {
    final base =
        collectionHref.endsWith('/') ? collectionHref : '$collectionHref/';
    return '$base$uid.ics';
  }
}

/// Termine gruppiert nach Tag – praktisch als `eventLoader` für table_calendar.
final eventsByDayProvider =
    Provider.autoDispose<Map<DateTime, List<CalendarEvent>>>((ref) {
  final asyncEvents = ref.watch(eventsControllerProvider);
  final map = <DateTime, List<CalendarEvent>>{};
  for (final e in asyncEvents.value ?? const []) {
    map.putIfAbsent(e.startDay, () => []).add(e);
  }
  return map;
});
