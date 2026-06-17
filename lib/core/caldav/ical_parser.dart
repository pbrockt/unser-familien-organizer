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
    this.recurrence,
    this.recurrenceId,
    this.exDates = const [],
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

  /// Minuten vor Beginn, zu denen erinnert werden soll (aus VALARM). `null` =
  /// keine Erinnerung.
  final int? reminderMinutes;

  /// Wiederholungsregel (RRULE), falls vorhanden – für die Expansion.
  final Recurrence? recurrence;

  /// RECURRENCE-ID: ist dieses VEVENT eine geänderte Einzel-Instanz einer
  /// Serie (Override), steht hier das ursprüngliche Startdatum der Instanz.
  final DateTime? recurrenceId;

  /// EXDATE: ausgenommene Termine der Serie (gelöschte Einzel-Instanzen).
  final List<DateTime> exDates;

  /// Ist dieses VEVENT ein Override (geänderte Einzel-Instanz)?
  bool get isOverride => recurrenceId != null;
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

  /// enough_icalendar entescaped TEXT-Werte (SUMMARY/LOCATION/DESCRIPTION) beim
  /// Parsen **nicht**, sodass z.B. ein Komma als „\," ankommt. Hier rückgängig
  /// machen (RFC 5545: \\ \; \, \n).
  static String? _unescapeText(String? v) {
    if (v == null || !v.contains('\\')) return v;
    final sb = StringBuffer();
    for (var i = 0; i < v.length; i++) {
      final ch = v[i];
      if (ch == '\\' && i + 1 < v.length) {
        final next = v[i + 1];
        switch (next) {
          case 'n':
          case 'N':
            sb.write('\n');
          case ',':
            sb.write(',');
          case ';':
            sb.write(';');
          case '\\':
            sb.write('\\');
          default:
            sb.write(next);
        }
        i++;
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  /// Liest die relative Erinnerungszeit (Minuten vor Beginn) aus einem VALARM
  /// mit negativem TRIGGER (z. B. `TRIGGER:-PT15M`, `-PT1H`). `null` = keine.
  static int? _alarmMinutes(VComponent c) {
    final text = c.toString();
    final m =
        RegExp(r'TRIGGER[^:\r\n]*:-PT(?:(\d+)H)?(?:(\d+)M)?').firstMatch(text);
    if (m == null) return null;
    final h = int.tryParse(m.group(1) ?? '') ?? 0;
    final min = int.tryParse(m.group(2) ?? '') ?? 0;
    final total = h * 60 + min;
    return total > 0 ? total : null;
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
        final summary = _unescapeText(c.summary)?.trim();
        result.add(ParsedEvent(
          uid: c.uid,
          summary: (summary != null && summary.isNotEmpty)
              ? summary
              : '(ohne Titel)',
          start: start,
          end: end,
          description: _unescapeText(c.description),
          location: _unescapeText(c.location),
          allDay: _looksAllDay(start, end),
          isRecurring: c.recurrenceRule != null,
          recurrence: c.recurrenceRule,
          recurrenceId: c.recurrenceId,
          exDates: c.excludingRecurrenceDates
                  ?.map((d) => d.dateTime)
                  .whereType<DateTime>()
                  .toList() ??
              const [],
          reminderMinutes: _alarmMinutes(c),
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
        final todoSummary = _unescapeText(c.summary)?.trim();
        result.add(ParsedTodo(
          uid: c.uid,
          summary: (todoSummary != null && todoSummary.isNotEmpty)
              ? todoSummary
              : '(ohne Titel)',
          description: _unescapeText(c.description),
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

  /// Setzt den Erledigt-Status eines VTODO im gegebenen iCal-Body und gibt
  /// den neuen, vollständigen iCal-Text zurück (zum Zurückschreiben per PUT).
  ///
  /// Erledigt → STATUS:COMPLETED, COMPLETED=jetzt, PERCENT-COMPLETE=100.
  /// Offen    → STATUS:NEEDS-ACTION, COMPLETED entfernt, PERCENT-COMPLETE=0.
  String toggleTodoCompletion(String icalData, {required bool completed}) {
    final root = VComponent.parse(icalData);
    final components = root is VCalendar ? root.children : [root];
    for (final c in components) {
      if (c is VTodo) {
        c.status =
            completed ? TodoStatus.completed : TodoStatus.needsAction;
        c.completed = completed ? DateTime.now() : null;
        c.percentComplete = completed ? 100 : 0;
      }
    }
    return root.toString();
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
