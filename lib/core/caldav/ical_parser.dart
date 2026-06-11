import 'package:enough_icalendar/enough_icalendar.dart';

/// Ein geparstes Kalender-Ereignis (VEVENT) – reines Dart, kein Flutter.
class ParsedEvent {
  const ParsedEvent({
    required this.uid,
    required this.summary,
    required this.start,
    this.end,
    this.description,
    this.location,
    this.allDay = false,
    this.isRecurring = false,
  });

  final String uid;
  final String summary;
  final DateTime start;
  final DateTime? end;
  final String? description;
  final String? location;
  final bool allDay;
  final bool isRecurring;
}

/// Eine geparste Aufgabe / ein Einkaufsartikel (VTODO).
class ParsedTodo {
  const ParsedTodo({
    required this.uid,
    required this.summary,
    this.description,
    this.due,
    this.completed = false,
    this.priority,
    this.categories = const [],
  });

  final String uid;
  final String summary;
  final String? description;
  final DateTime? due;
  final bool completed;
  final int? priority;
  final List<String> categories;
}

/// Parst iCalendar-Objekte (RFC 5545) mit `enough_icalendar`.
///
/// Ein CalDAV-Objekt enthält i.d.R. ein VCALENDAR mit einer oder mehreren
/// Komponenten (VEVENT/VTODO + evtl. Ausnahme-Instanzen von Serien).
class IcalParser {
  const IcalParser();

  Iterable<VComponent> _components(String icalData) {
    final parsed = VComponent.parse(icalData);
    if (parsed is VCalendar) return parsed.children;
    return [parsed];
  }

  /// Alle VEVENTs aus einem iCal-Body. Fehlerhafte Objekte werden
  /// übersprungen, statt den ganzen Sync zu kippen.
  List<ParsedEvent> parseEvents(String icalData) {
    final result = <ParsedEvent>[];
    try {
      for (final c in _components(icalData)) {
        if (c is! VEvent) continue;
        final start = c.start;
        if (start == null) continue;
        final end = c.end;
        result.add(ParsedEvent(
          uid: c.uid,
          summary: c.summary?.trim().isNotEmpty == true
              ? c.summary!.trim()
              : '(ohne Titel)',
          start: start,
          end: end,
          description: c.description,
          location: c.location,
          allDay: _looksAllDay(start, end),
          isRecurring: c.recurrenceRule != null,
        ));
      }
    } catch (_) {
      // Unparsebares Objekt ignorieren.
    }
    return result;
  }

  /// Alle VTODOs aus einem iCal-Body.
  List<ParsedTodo> parseTodos(String icalData) {
    final result = <ParsedTodo>[];
    try {
      for (final c in _components(icalData)) {
        if (c is! VTodo) continue;
        result.add(ParsedTodo(
          uid: c.uid,
          summary: c.summary?.trim().isNotEmpty == true
              ? c.summary!.trim()
              : '(ohne Titel)',
          description: c.description,
          due: c.due,
          completed: c.status == TodoStatus.completed,
          priority: c.priorityInt,
          categories: c.categories ?? const [],
        ));
      }
    } catch (_) {
      // Unparsebares Objekt ignorieren.
    }
    return result;
  }

  /// Heuristik: Ganztags-Events haben Mitternacht als Start (DTSTART;VALUE=DATE)
  /// und enden – falls vorhanden – ebenfalls auf Mitternacht.
  bool _looksAllDay(DateTime start, DateTime? end) {
    bool midnight(DateTime d) =>
        d.hour == 0 && d.minute == 0 && d.second == 0;
    if (!midnight(start)) return false;
    if (end == null) return true;
    return midnight(end);
  }
}
