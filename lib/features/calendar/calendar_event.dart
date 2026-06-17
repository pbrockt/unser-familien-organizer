import 'package:flutter/material.dart';

import '../../core/caldav/ical_parser.dart';

/// Anzeige-Modell eines Termins: geparstes VEVENT + Herkunft (Kalenderfarbe,
/// -name und -href aus der CalDAV-Collection) sowie alles zum Zurückschreiben
/// (Objekt-URL, ETag, roher iCal-Body).
class CalendarEvent {
  const CalendarEvent({
    required this.uid,
    required this.summary,
    required this.start,
    this.end,
    this.description,
    this.location,
    this.allDay = false,
    this.isRecurring = false,
    this.color,
    this.calendarName = '',
    this.calendarHref = '',
    this.objectHref = '',
    this.etag = '',
    this.rawIcal = '',
    this.recurrenceDate,
    this.reminderMinutes,
  });

  final String uid;
  final String summary;
  final DateTime start;
  final DateTime? end;
  final String? description;
  final String? location;
  final bool allDay;
  final bool isRecurring;
  final Color? color;
  final String calendarName;

  /// Href der Kalender-Collection (für neue Objekte / Zuordnung).
  final String calendarHref;

  /// Href des CalDAV-Objekts (.ics) – Ziel für PUT/DELETE.
  final String objectHref;

  /// ETag zur Konflikterkennung beim Schreiben.
  final String etag;

  /// Vollständiger iCal-Body (wird beim Bearbeiten zugrunde gelegt).
  final String rawIcal;

  /// Ursprüngliches Startdatum dieser Serien-Instanz (für „nur diesen Termin
  /// löschen" via EXDATE). Bei Einzelterminen `null`.
  final DateTime? recurrenceDate;

  /// Minuten vor Beginn für die Erinnerung (VALARM). `null` = keine Erinnerung.
  final int? reminderMinutes;

  factory CalendarEvent.fromParsed(
    ParsedEvent e, {
    Color? color,
    String calendarName = '',
    String calendarHref = '',
    String objectHref = '',
    String etag = '',
    String rawIcal = '',
    bool? isRecurring,
    DateTime? recurrenceDate,
  }) {
    return CalendarEvent(
      uid: e.uid,
      summary: e.summary,
      start: e.start,
      end: e.end,
      description: e.description,
      location: e.location,
      allDay: e.allDay,
      isRecurring: isRecurring ?? e.isRecurring,
      color: color,
      calendarName: calendarName,
      calendarHref: calendarHref,
      objectHref: objectHref,
      etag: etag,
      rawIcal: rawIcal,
      recurrenceDate: recurrenceDate,
      reminderMinutes: e.reminderMinutes,
    );
  }

  CalendarEvent copyWith({
    DateTime? start,
    DateTime? end,
    DateTime? recurrenceDate,
    bool? isRecurring,
    Color? color,
  }) {
    return CalendarEvent(
      uid: uid,
      summary: summary,
      start: start ?? this.start,
      end: end ?? this.end,
      description: description,
      location: location,
      allDay: allDay,
      isRecurring: isRecurring ?? this.isRecurring,
      color: color ?? this.color,
      calendarName: calendarName,
      calendarHref: calendarHref,
      objectHref: objectHref,
      etag: etag,
      rawIcal: rawIcal,
      recurrenceDate: recurrenceDate ?? this.recurrenceDate,
      reminderMinutes: reminderMinutes,
    );
  }

  /// Tag (ohne Uhrzeit) des Termin-Starts – für die Gruppierung im Kalender.
  DateTime get startDay => DateTime(start.year, start.month, start.day);

  /// Letzter Tag, an dem der Termin (noch) läuft. Bei Ganztags-Terminen ist
  /// DTEND exklusiv (= Folgetag), daher ein Tag abgezogen.
  DateTime get endDayInclusive {
    final e = end;
    if (e == null) return startDay;
    var ref = e;
    if (allDay) ref = ref.subtract(const Duration(days: 1));
    final d = DateTime(ref.year, ref.month, ref.day);
    return d.isBefore(startDay) ? startDay : d;
  }

  /// Erstreckt sich der Termin über mehr als einen Tag?
  bool get isMultiDay => endDayInclusive != startDay;

  /// Läuft der Termin am gegebenen Tag (für mehrtägige Termine)?
  bool occursOn(DateTime day) =>
      !day.isBefore(startDay) && !day.isAfter(endDayInclusive);

  /// Ist der Termin bereits vorbei (zum Ausblenden in Listen)?
  /// Zeitgebunden: Ende (oder Start, falls kein Ende) liegt vor [now].
  /// Ganztägig/mehrtägig: der letzte Tag liegt vor dem heutigen Tag.
  bool hasPassed(DateTime now) {
    if (allDay || isMultiDay) {
      final today = DateTime(now.year, now.month, now.day);
      return endDayInclusive.isBefore(today);
    }
    return (end ?? start).isBefore(now);
  }
}
