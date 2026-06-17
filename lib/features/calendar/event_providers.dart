import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../core/caldav/caldav_repository.dart';
import '../../core/caldav/ical_builder.dart';
import '../../core/sync/sync_status.dart';
import '../members/member_settings.dart';
import 'calendar_event.dart';
import 'events_builder.dart';

/// Sprungziel für den Kalender (von der Startseite ausgelöst).
class CalendarJumpTarget {
  const CalendarJumpTarget(this.date, {this.openDay = true});

  final DateTime date;

  /// true = direkt die Tagesansicht öffnen (z.B. Termin/Countdown angetippt),
  /// false = nur im Monat zu diesem Tag springen (2-Wochen-Übersicht angetippt).
  final bool openDay;
}

/// Offenes Sprungziel für die Kalenderansicht – `null` = kein Sprung offen.
class CalendarJump extends Notifier<CalendarJumpTarget?> {
  @override
  CalendarJumpTarget? build() => null;

  void set(CalendarJumpTarget? target) => state = target;
}

final calendarJumpProvider =
    NotifierProvider<CalendarJump, CalendarJumpTarget?>(CalendarJump.new);

/// Aktuell im Kalender ausgewählter Tag – wird genutzt, um „Neuer Termin" (über
/// das „+") mit dem gewählten Tag statt „heute" vorzubelegen.
class CalendarSelectedDay extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void set(DateTime day) => state = DateTime(day.year, day.month, day.day);
}

final calendarSelectedDayProvider =
    NotifierProvider<CalendarSelectedDay, DateTime>(CalendarSelectedDay.new);

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

  /// Setzt Sync-Status/Diagnose (über Microtask, um nicht während des
  /// Provider-Builds einen anderen Provider zu verändern).
  void _post(void Function(SyncStatusController c) fn) {
    Future.microtask(() {
      if (_disposed) return;
      fn(ref.read(syncStatusProvider.notifier));
    });
  }

  void _setSyncing() => _post((c) => c.setSyncing());
  void _setOnline() => _post((c) => c.setOnline());
  void _setOffline(Object e) => _post((c) => c.setOffline(e.toString()));

  /// Wertet das Sync-Ergebnis aus: Status (online/offline) + Debug-Bericht.
  void _applySyncResult(CalDavSnapshot snap) {
    if (snap.fromCache && snap.error != null) {
      _setOffline(snap.error!);
    } else {
      _setOnline();
    }
    _post((c) => c.setDebug(snap.debugReport()));
  }

  @override
  Future<List<CalendarEvent>> build() async {
    ref.onDispose(() => _disposed = true);
    final account = await ref.watch(accountProvider.future);
    if (account == null) {
      _setOffline('Nicht mit der Nextcloud verbunden.');
      return const [];
    }
    final repo = ref.watch(caldavRepositoryProvider);

    // Gecachte Daten sofort zeigen, im Hintergrund frisch synchronisieren.
    final cached = await repo.cachedSnapshot(account);
    if (cached == null) {
      // Erststart ohne Cache: einmalig synchron laden.
      _setSyncing();
      try {
        final fresh = await repo.sync(account);
        _applySyncResult(fresh);
        return buildEventsFromSnapshot(fresh);
      } catch (e) {
        _setOffline(e);
        rethrow;
      }
    }
    Future.microtask(() => _backgroundRefresh(account, repo));
    return buildEventsFromSnapshot(cached);
  }

  Future<void> _backgroundRefresh(
      NextcloudAccount account, CalDavRepository repo) async {
    _setSyncing();
    try {
      final fresh = await repo.sync(account);
      if (_disposed) return;
      _applySyncResult(fresh);
      state = AsyncData(buildEventsFromSnapshot(fresh));
    } catch (e) {
      // Offline o.ä. → gecachter Stand bleibt sichtbar.
      _setOffline(e);
    }
  }

  /// Nach einer lokalen Änderung: **sofort** aus dem bereits aktualisierten
  /// Cache neu aufbauen, damit der Termin ohne manuelles „Aktualisieren"
  /// erscheint.
  ///
  /// Bewusst KEIN sofortiger Server-Sync: `putObject`/`deleteObject` haben den
  /// Cache schon aktualisiert; ein direkter REPORT würde den Cache evtl. mit
  /// einem noch nicht propagierten Server-Stand überschreiben (dann „verschwände"
  /// der neue Termin). Der Abgleich passiert über den Hintergrund-Sync, den
  /// „Aktualisieren"-Knopf bzw. den nächsten App-Start.
  Future<void> _refresh(NextcloudAccount account) async {
    final repo = ref.read(caldavRepositoryProvider);
    final cached = await repo.cachedSnapshot(account);
    if (_disposed) return;
    if (cached != null) {
      state = AsyncData(buildEventsFromSnapshot(cached));
    }
    _setOnline();
  }


  /// Löscht nur eine einzelne Serien-Instanz: setzt ein EXDATE und schreibt
  /// das Objekt zurück (statt die ganze Serie zu löschen).
  Future<void> deleteOccurrence(CalendarEvent event,
      {bool force = false}) async {
    final date = event.recurrenceDate;
    if (date == null) return deleteEvent(event, force: force);

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
      force: force,
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
    int? reminderMinutes,
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
      reminderMinutes: reminderMinutes,
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
    int? reminderMinutes,
    bool force = false,
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
      reminderMinutes: reminderMinutes,
    );
    await repo.putObject(
      account,
      event.objectHref,
      ical,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
      force: force,
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
    bool force = false,
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
          location: location,
          force: force);
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
      force: force,
    );
    await _refresh(account);
  }

  /// Verschiebt einen Termin in einen anderen Kalender (andere Collection) und
  /// übernimmt dabei die geänderten Felder. Da CalDAV-Objekte an ihre Collection
  /// gebunden sind, wird das Objekt in der neuen Collection angelegt und in der
  /// alten gelöscht (UID/Dateiname bleiben erhalten).
  Future<void> moveEvent(
    CalendarEvent event, {
    required String newCalendarHref,
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
    int? reminderMinutes,
    bool force = false,
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
      reminderMinutes: reminderMinutes,
    );

    final fileName = event.objectHref.split('/').last;
    final base = newCalendarHref.endsWith('/')
        ? newCalendarHref
        : '$newCalendarHref/';
    final newHref = '$base$fileName';

    // Erst neu anlegen, dann altes Objekt entfernen (kein Datenverlust, falls
    // der zweite Schritt fehlschlägt).
    await repo.putObject(account, newHref, ical);
    await repo.deleteObject(
      account,
      event.objectHref,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
      force: true,
    );
    await _refresh(account);
  }

  Future<void> deleteEvent(CalendarEvent event, {bool force = false}) async {
    final account = await ref.read(accountProvider.future);
    if (account == null) return;
    final repo = ref.read(caldavRepositoryProvider);

    await repo.deleteObject(
      account,
      event.objectHref,
      ifMatchEtag: event.etag.isEmpty ? null : event.etag,
      force: force,
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
