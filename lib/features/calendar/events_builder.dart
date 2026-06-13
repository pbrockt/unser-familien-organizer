import '../../core/caldav/caldav_repository.dart';
import '../../core/caldav/ical_parser.dart';
import '../../core/caldav/recurrence_expander.dart';
import '../../shared/utils/hex_color.dart';
import 'calendar_event.dart';

const _parser = IcalParser();
const _expander = RecurrenceExpander();

DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

CalendarEvent _occurrence(
    CalendarEvent base, DateTime start, Duration? duration) {
  return base.copyWith(
    start: start,
    end: duration == null ? null : start.add(duration),
    isRecurring: true,
    recurrenceDate: start,
  );
}

/// Baut aus einem CalDAV-Snapshot die anzuzeigenden Termine, inkl.
/// Serien-Expansion (RRULE), Overrides (RECURRENCE-ID) und Ausnahmen (EXDATE).
///
/// Reine Funktion ohne Riverpod – nutzbar in der UI **und** im
/// Hintergrund-Isolate.
List<CalendarEvent> buildEventsFromSnapshot(CalDavSnapshot snapshot) {
  final eventCollections =
      snapshot.collections.where((c) => c.supportsEvents);

  // Expansions-Fenster für Serientermine: ~2 Monate zurück bis ~14 voraus.
  final today = DateTime.now();
  final windowStart = DateTime(today.year, today.month, today.day)
      .subtract(const Duration(days: 60));
  final windowEnd = windowStart.add(const Duration(days: 485));

  final events = <CalendarEvent>[];
  for (final col in eventCollections) {
    final color = parseHexColor(col.color);
    final objects = snapshot.objectsOf(col.href);
    for (final obj in objects) {
      final parsedList = _parser.parseEvents(obj.icalData);
      final overriddenDays = parsedList
          .where((e) => e.isOverride)
          .map((e) => _dayKey(e.recurrenceId!))
          .toSet();

      for (final parsed in parsedList) {
        final base = CalendarEvent.fromParsed(
          parsed,
          color: color,
          calendarName: col.displayName,
          calendarHref: col.href,
          objectHref: obj.href,
          etag: obj.etag,
          rawIcal: obj.icalData,
        );

        if (parsed.isOverride) {
          events.add(base.copyWith(
            isRecurring: true,
            recurrenceDate: parsed.recurrenceId,
          ));
          continue;
        }

        final rule = parsed.recurrence;
        if (rule == null) {
          events.add(base);
          continue;
        }

        final excludedDays = parsed.exDates.map(_dayKey).toSet()
          ..addAll(overriddenDays);
        final duration = parsed.end?.difference(parsed.start);
        final occurrences = _expander.expand(
          parsed.start,
          rule,
          windowStart: windowStart,
          windowEnd: windowEnd,
        );
        if (occurrences.isEmpty) {
          events.add(base);
          continue;
        }
        for (final occ in occurrences) {
          if (excludedDays.contains(_dayKey(occ))) continue;
          events.add(_occurrence(base, occ, duration));
        }
      }
    }
  }
  events.sort((a, b) => a.start.compareTo(b.start));
  return events;
}
