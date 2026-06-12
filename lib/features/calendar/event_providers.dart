import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../core/caldav/caldav_repository.dart';
import '../../core/caldav/ical_builder.dart';
import '../../core/caldav/ical_parser.dart';
import '../../core/caldav/recurrence_expander.dart';
import '../../shared/utils/hex_color.dart';
import '../members/member_settings.dart';
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

  bool _disposed = false;

  @override
  Future<List<CalendarEvent>> build() async {
    ref.onDispose(() => _disposed = true);
    final account = await ref.watch(accountProvider.future);
    if (account == null) return const [];
    final repo = ref.watch(caldavRepositoryProvider);

    // Gecachte Daten sofort zeigen, im Hintergrund frisch synchronisieren.
    final cached = await repo.cachedSnapshot(account);
    if (cached == null) {
      // Erststart ohne Cache: einmalig synchron laden.
      return _buildEvents(await repo.sync(account));
    }
    Future.microtask(() => _backgroundRefresh(account, repo));
    return _buildEvents(cached);
  }

  Future<void> _backgroundRefresh(
      NextcloudAccount account, CalDavRepository repo) async {
    try {
      final fresh = await repo.sync(account);
      if (_disposed) return;
      state = AsyncData(_buildEvents(fresh));
    } catch (_) {
      // Offline o.ä. → gecachter Stand bleibt sichtbar.
    }
  }

  /// Nach einer Änderung: frisch synchronisieren (Delta) und State setzen.
  Future<void> _refresh(NextcloudAccount account) async {
    final repo = ref.read(caldavRepositoryProvider);
    final fresh = await repo.sync(account);
    if (_disposed) return;
    state = AsyncData(_buildEvents(fresh));
  }

  /// Baut aus einem Snapshot die anzuzeigenden Termine (inkl. Serien-Expansion).
  List<CalendarEvent> _buildEvents(CalDavSnapshot snapshot) {
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
        final parsedList = _parser.parseEvents(obj.icalData);
        // Tage, die durch geänderte Einzel-Instanzen (Override) ersetzt sind.
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

          // Geänderte Einzel-Instanz: als eigener Termin (mit Originaldatum).
          if (parsed.isOverride) {
            events.add(base.copyWith(
              isRecurring: true,
              recurrenceDate: parsed.recurrenceId,
            ));
            continue;
          }

          final rule = parsed.recurrence;
          if (rule == null) {
            events.add(base); // normaler Einzeltermin
            continue;
          }

          // Serientermin expandieren; EXDATE + überschriebene Tage auslassen.
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
            events.add(base); // Fallback: wenigstens die Basis zeigen.
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

  /// Erzeugt eine Serien-Instanz aus dem Basistermin mit verschobenem Start.
  CalendarEvent _occurrence(
      CalendarEvent base, DateTime start, Duration? duration) {
    return base.copyWith(
      start: start,
      end: duration == null ? null : start.add(duration),
      isRecurring: true,
      recurrenceDate: start, // Originaldatum dieser Instanz (für EXDATE)
    );
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Löscht nur eine einzelne Serien-Instanz: setzt ein EXDATE und schreibt
  /// das Objekt zurück (statt die ganze Serie zu löschen).
  Future<void> deleteOccurrence(CalendarEvent event) async {
    final date = event.recurrenceDate;
    if (date == null) return deleteEvent(event); // kein Serien-Kontext

    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    final ical = _builder.excludeOccurrence(
      event.rawIcal,
      date,
      allDay: event.allDay,
    );
    await repo.putObject(
      account,
      event.objectHref,
      ical,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
    );
    await _refresh(account);
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
    final repo = ref.read(caldavRepositoryProvider);

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
    await repo.putObject(account, _objectHref(calendarHref, uid), ical);
    await _refresh(account);
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
    final repo = ref.read(caldavRepositoryProvider);

    final ical = _builder.updateEvent(
      event.rawIcal,
      summary: summary,
      start: start,
      end: end,
      allDay: allDay,
      description: description,
      location: location,
    );
    await repo.putObject(
      account,
      event.objectHref,
      ical,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
    );
    await _refresh(account);
  }

  /// Ändert nur eine einzelne Serien-Instanz (legt einen Override an), ohne
  /// die restliche Serie zu verändern.
  Future<void> updateOccurrence(
    CalendarEvent event, {
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
  }) async {
    final recurrenceId = event.recurrenceDate;
    if (recurrenceId == null) {
      // Kein Serien-Kontext → normale Aktualisierung.
      return updateEvent(event,
          summary: summary,
          start: start,
          end: end,
          allDay: allDay,
          description: description,
          location: location);
    }

    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    final ical = _builder.upsertOverride(
      event.rawIcal,
      recurrenceId: recurrenceId,
      summary: summary,
      start: start,
      end: end,
      allDay: allDay,
      description: description,
      location: location,
    );
    await repo.putObject(
      account,
      event.objectHref,
      ical,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
    );
    await _refresh(account);
  }

  Future<void> deleteEvent(CalendarEvent event) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    await repo.deleteObject(
      account,
      event.objectHref,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
    );
    await _refresh(account);
  }

  String _objectHref(String collectionHref, String uid) {
    final base =
        collectionHref.endsWith('/') ? collectionHref : '$collectionHref/';
    return '$base$uid.ics';
  }
}

/// Sichtbare Termine: wendet Mitglieder-Anpassungen an (eigene Farbe) und
/// blendet ausgeblendete Kalender aus.
final visibleEventsProvider = Provider.autoDispose<List<CalendarEvent>>((ref) {
  final events = ref.watch(eventsControllerProvider).value ?? const [];
  final settings = ref.watch(memberSettingsProvider).value ?? const {};
  if (settings.isEmpty) return events;
  final out = <CalendarEvent>[];
  for (final e in events) {
    final s = settings[e.calendarHref];
    if (s == null) {
      out.add(e);
      continue;
    }
    if (s.hidden) continue;
    final override = parseHexColor(s.colorHex);
    out.add(override != null ? e.copyWith(color: override) : e);
  }
  return out;
});

/// Termine gruppiert nach Tag – praktisch als `eventLoader` für table_calendar.
final eventsByDayProvider =
    Provider.autoDispose<Map<DateTime, List<CalendarEvent>>>((ref) {
  final visible = ref.watch(visibleEventsProvider);
  final map = <DateTime, List<CalendarEvent>>{};
  for (final e in visible) {
    // Mehrtägige Termine an jedem Tag eintragen (mit Sicherheitskappe).
    var day = e.startDay;
    final last = e.endDayInclusive;
    var guard = 0;
    while (!day.isAfter(last) && guard < 90) {
      map.putIfAbsent(day, () => []).add(e);
      day = day.add(const Duration(days: 1));
      guard++;
    }
  }
  return map;
});
