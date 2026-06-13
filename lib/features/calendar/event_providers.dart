import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../core/caldav/caldav_repository.dart';
import '../../core/caldav/ical_builder.dart';
import '../members/member_settings.dart';
import 'calendar_event.dart';
import 'events_builder.dart';

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
  static const _builder = IcalBuilder();

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
      return buildEventsFromSnapshot(await repo.sync(account));
    }
    Future.microtask(() => _backgroundRefresh(account, repo));
    return buildEventsFromSnapshot(cached);
  }

  Future<void> _backgroundRefresh(
      NextcloudAccount account, CalDavRepository repo) async {
    try {
      final fresh = await repo.sync(account);
      if (_disposed) return;
      state = AsyncData(buildEventsFromSnapshot(fresh));
    } catch (_) {
      // Offline o.ä. → gecachter Stand bleibt sichtbar.
    }
  }

  /// Nach einer Änderung: frisch synchronisieren (Delta) und State setzen.
  Future<void> _refresh(NextcloudAccount account) async {
    final repo = ref.read(caldavRepositoryProvider);
    final fresh = await repo.sync(account);
    if (_disposed) return;
    state = AsyncData(buildEventsFromSnapshot(fresh));
  }


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
  return filterVisibleEvents(events, settings);
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
