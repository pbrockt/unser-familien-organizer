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

  factory CalendarEvent.fromParsed(
    ParsedEvent e, {
    Color? color,
    String calendarName = '',
    String calendarHref = '',
    String objectHref = '',
    String etag = '',
    String rawIcal = '',
  }) {
    return CalendarEvent(
      uid: e.uid,
      summary: e.summary,
      start: e.start,
      end: e.end,
      description: e.description,
      location: e.location,
      allDay: e.allDay,
      isRecurring: e.isRecurring,
      color: color,
      calendarName: calendarName,
      calendarHref: calendarHref,
      objectHref: objectHref,
      etag: etag,
      rawIcal: rawIcal,
    );
  }

  /// Tag (ohne Uhrzeit) des Termin-Starts – für die Gruppierung im Kalender.
  DateTime get startDay => DateTime(start.year, start.month, start.day);
}
