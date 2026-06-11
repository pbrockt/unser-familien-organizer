import 'package:flutter/material.dart';

import '../../core/caldav/ical_parser.dart';

/// Anzeige-Modell eines Termins: geparstes VEVENT + Herkunft (Kalenderfarbe
/// und -name aus der CalDAV-Collection).
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

  factory CalendarEvent.fromParsed(
    ParsedEvent e, {
    Color? color,
    String calendarName = '',
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
    );
  }

  /// Tag (ohne Uhrzeit) des Termin-Starts – für die Gruppierung im Kalender.
  DateTime get startDay => DateTime(start.year, start.month, start.day);
}
