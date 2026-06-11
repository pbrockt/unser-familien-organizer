import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:uuid/uuid.dart';

/// Erzeugt und bearbeitet iCalendar-Objekte (VTODO/VEVENT) als vollständige
/// VCALENDAR-Texte zum Schreiben per CalDAV-PUT.
class IcalBuilder {
  const IcalBuilder();

  static const _uuid = Uuid();
  static const _productId = '-//FamilyPlanner//DE';

  /// Neue, eindeutige UID (auch als Dateiname `<uid>.ics` verwendbar).
  String newUid() => _uuid.v4();

  /// Baut ein neues VTODO (offene Aufgabe).
  String buildTodo({
    required String uid,
    required String summary,
    DateTime? due,
    String? description,
  }) {
    final calendar = VCalendar()
      ..version = '2.0'
      ..productId = _productId;
    final todo = VTodo(parent: calendar);
    calendar.children.add(todo);
    todo
      ..timeStamp = DateTime.now()
      ..uid = uid
      ..summary = summary
      ..status = TodoStatus.needsAction;
    if (due != null) todo.due = due;
    if (description != null && description.isNotEmpty) {
      todo.description = description;
    }
    return calendar.toString();
  }

  /// Baut ein neues VEVENT (Termin).
  String buildEvent({
    required String uid,
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
  }) {
    final calendar = VCalendar()
      ..version = '2.0'
      ..productId = _productId;
    final event = VEvent(parent: calendar);
    calendar.children.add(event);

    final effectiveEnd = end ??
        (allDay
            ? start.add(const Duration(days: 1))
            : start.add(const Duration(hours: 1)));

    event
      ..timeStamp = DateTime.now()
      ..uid = uid
      ..summary = summary
      ..start = start
      ..end = effectiveEnd;
    if (description != null && description.isNotEmpty) {
      event.description = description;
    }
    if (location != null && location.isNotEmpty) {
      event.location = location;
    }

    final text = calendar.toString();
    return allDay ? _applyAllDay(text, start, effectiveEnd) : text;
  }

  /// Ändert ein bestehendes VEVENT und behält den Rest (z.B. RRULE) erhalten.
  String updateEvent(
    String rawIcal, {
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
  }) {
    final root = VComponent.parse(rawIcal);
    final components = root is VCalendar ? root.children : [root];
    final effectiveEnd = end ??
        (allDay
            ? start.add(const Duration(days: 1))
            : start.add(const Duration(hours: 1)));
    for (final c in components) {
      if (c is VEvent) {
        c
          ..summary = summary
          ..start = start
          ..end = effectiveEnd
          ..description =
              (description == null || description.isEmpty) ? null : description
          ..location =
              (location == null || location.isEmpty) ? null : location
          ..timeStamp = DateTime.now();
      }
    }
    final text = root.toString();
    return allDay ? _applyAllDay(text, start, effectiveEnd) : text;
  }

  /// Schreibt DTSTART/DTEND als reine Datumswerte (VALUE=DATE) um – so erkennt
  /// Nextcloud einen echten Ganztags-Termin.
  String _applyAllDay(String text, DateTime start, DateTime end) {
    String d(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}'
        '${x.month.toString().padLeft(2, '0')}'
        '${x.day.toString().padLeft(2, '0')}';
    return text
        .replaceAll(RegExp(r'DTSTART[^\r\n]*'), 'DTSTART;VALUE=DATE:${d(start)}')
        .replaceAll(RegExp(r'DTEND[^\r\n]*'), 'DTEND;VALUE=DATE:${d(end)}');
  }

  /// Ändert SUMMARY/DUE/DESCRIPTION eines bestehenden VTODO und behält den
  /// Rest des Objekts erhalten.
  String updateTodo(
    String rawIcal, {
    required String summary,
    DateTime? due,
    bool clearDue = false,
    String? description,
  }) {
    final root = VComponent.parse(rawIcal);
    final components = root is VCalendar ? root.children : [root];
    for (final c in components) {
      if (c is VTodo) {
        c.summary = summary;
        if (clearDue) {
          c.due = null;
        } else if (due != null) {
          c.due = due;
        }
        c.description =
            (description == null || description.isEmpty) ? null : description;
        c.timeStamp = DateTime.now();
      }
    }
    return root.toString();
  }
}
