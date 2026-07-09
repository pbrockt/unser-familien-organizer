import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:uuid/uuid.dart';

/// Erzeugt und bearbeitet iCalendar-Objekte (VTODO/VEVENT) als vollständige
/// VCALENDAR-Texte zum Schreiben per CalDAV-PUT.
class IcalBuilder {
  const IcalBuilder();

  static const _uuid = Uuid();
  static const _productId = '-//Unser Familien-Organizer//DE';

  /// Neue, eindeutige UID (auch als Dateiname `<uid>.ics` verwendbar).
  String newUid() => _uuid.v4();

  /// Baut ein neues VTODO (offene Aufgabe).
  String buildTodo({
    required String uid,
    required String summary,
    DateTime? due,
    String? description,
    String? rrule,
    String? relatedTo,
    int? priority,
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
    if (priority != null) todo.priorityInt = priority;
    if (description != null && description.isNotEmpty) {
      todo.description = description;
    }
    var text = _withRruleTodo(calendar.toString(), rrule);
    text = _withRelatedTodo(text, relatedTo);
    return text;
  }

  /// Fügt eine `RRULE:`-Zeile vor dem ersten `END:VTODO` ein (wiederkehrende
  /// Aufgabe).
  String _withRruleTodo(String text, String? rrule) {
    if (rrule == null || rrule.isEmpty) return text;
    final idx = text.indexOf('END:VTODO');
    if (idx < 0) return text;
    return '${text.substring(0, idx)}RRULE:$rrule\r\n${text.substring(idx)}';
  }

  /// Fügt eine `RELATED-TO:<uid>`-Zeile vor dem ersten `END:VTODO` ein
  /// (Verknüpfung zu einem Termin).
  String _withRelatedTodo(String text, String? uid) {
    if (uid == null || uid.isEmpty) return text;
    final idx = text.indexOf('END:VTODO');
    if (idx < 0) return text;
    return '${text.substring(0, idx)}RELATED-TO:$uid\r\n${text.substring(idx)}';
  }

  String _stripRelated(String text) =>
      text.replaceAll(RegExp(r'RELATED-TO[^\r\n]*\r?\n'), '');

  /// Baut ein neues VEVENT (Termin). [rrule] = Wiederholungsregel ohne Präfix,
  /// z. B. `FREQ=WEEKLY` (null = Einzeltermin).
  String buildEvent({
    required String uid,
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
    int? reminderMinutes,
    String? rrule,
    List<String>? categories,
  }) {
    final calendar = VCalendar()
      ..version = '2.0'
      ..productId = _productId;
    final event = VEvent(parent: calendar);
    calendar.children.add(event);

    final effectiveEnd =
        end ??
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
    final withDay = allDay ? _applyAllDay(text, start, effectiveEnd) : text;
    final withCat = _withCategories(withDay, categories);
    final withRrule = _withRrule(withCat, rrule);
    return _withAlarm(withRrule, reminderMinutes, summary);
  }

  /// Ersetzt die `CATEGORIES` eines VEVENT: entfernt vorhandene Zeilen und
  /// setzt die neuen (leere Liste = keine Kategorien). Der Rest des Objekts
  /// bleibt unverändert.
  String setEventCategories(String rawIcal, List<String> categories) {
    final stripped = rawIcal.replaceAll(RegExp(r'CATEGORIES[^\r\n]*\r?\n'), '');
    return _withCategories(stripped, categories);
  }

  /// Fügt eine `CATEGORIES:a,b`-Zeile vor dem ersten `END:VEVENT` ein.
  String _withCategories(String text, List<String>? categories) {
    if (categories == null || categories.isEmpty) return text;
    final value = categories.map(_escapeText).join(',');
    final idx = text.indexOf('END:VEVENT');
    if (idx < 0) return text;
    return '${text.substring(0, idx)}CATEGORIES:$value\r\n'
        '${text.substring(idx)}';
  }

  /// Fügt eine `RRULE:`-Zeile vor dem ersten `END:VEVENT` ein (Serientermin).
  String _withRrule(String text, String? rrule) {
    if (rrule == null || rrule.isEmpty) return text;
    final idx = text.indexOf('END:VEVENT');
    if (idx < 0) return text;
    return '${text.substring(0, idx)}RRULE:$rrule\r\n${text.substring(idx)}';
  }

  /// Ändert ein bestehendes VEVENT. Behält standardmäßig eine vorhandene RRULE.
  /// Mit [updateRrule] = true wird die Wiederholung ersetzt: bestehende RRULE
  /// entfernt und – falls [rrule] nicht null/leer – die neue gesetzt.
  String updateEvent(
    String rawIcal, {
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
    int? reminderMinutes,
    String? rrule,
    bool updateRrule = false,
  }) {
    final root = VComponent.parse(rawIcal);
    final components = root is VCalendar ? root.children : [root];
    final effectiveEnd =
        end ??
        (allDay
            ? start.add(const Duration(days: 1))
            : start.add(const Duration(hours: 1)));
    for (final c in components) {
      // Nur den Master/Einzeltermin ändern, Override-Instanzen unangetastet.
      if (c is VEvent && c.recurrenceId == null) {
        c
          ..summary = summary
          ..start = start
          ..end = effectiveEnd
          ..description = (description == null || description.isEmpty)
              ? null
              : description
          ..location = (location == null || location.isEmpty) ? null : location
          ..timeStamp = DateTime.now();
      }
    }
    var text = root.toString();
    if (updateRrule) {
      text = _withRrule(_stripRrule(text), rrule);
    }
    final withDay = allDay ? _applyAllDay(text, start, effectiveEnd) : text;
    return _withAlarm(withDay, reminderMinutes, summary);
  }

  /// Entfernt alle `RRULE:`-Zeilen.
  String _stripRrule(String text) =>
      text.replaceAll(RegExp(r'RRULE:[^\r\n]*\r?\n'), '');

  /// Setzt/entfernt einen VALARM (DISPLAY) mit relativem Trigger „[minutes] vor
  /// Beginn". Bestehende VALARM-Blöcke werden zuerst entfernt.
  String _withAlarm(String text, int? minutes, String summary) {
    final cleaned = text.replaceAll(
      RegExp(r'BEGIN:VALARM.*?END:VALARM\r?\n', dotAll: true),
      '',
    );
    if (minutes == null || minutes <= 0) return cleaned;
    final desc = _escapeText(summary.isEmpty ? 'Erinnerung' : summary);
    final block =
        'BEGIN:VALARM\r\n'
        'ACTION:DISPLAY\r\n'
        'DESCRIPTION:$desc\r\n'
        'TRIGGER:-PT${minutes}M\r\n'
        'END:VALARM\r\n';
    final idx = cleaned.indexOf('END:VEVENT');
    if (idx < 0) return cleaned;
    return cleaned.substring(0, idx) + block + cleaned.substring(idx);
  }

  String _escapeText(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');

  /// Legt für eine Serie eine geänderte Einzel-Instanz (Override) an bzw.
  /// ersetzt eine bestehende: ein zusätzliches VEVENT mit derselben UID und
  /// `RECURRENCE-ID = recurrenceId` (= Originaldatum der Instanz). Dadurch wird
  /// nur dieser eine Termin verschoben/geändert, nicht die ganze Serie.
  String upsertOverride(
    String rawIcal, {
    required DateTime recurrenceId,
    required String summary,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    String? description,
    String? location,
  }) {
    final root = VComponent.parse(rawIcal);
    if (root is! VCalendar) return rawIcal;

    // UID der Serie ermitteln (Master bevorzugt).
    String? uid;
    for (final c in root.children) {
      if (c is VEvent) {
        uid ??= c.uid;
        if (c.recurrenceRule != null) {
          uid = c.uid;
          break;
        }
      }
    }
    uid ??= newUid();

    // Bestehenden Override mit gleicher RECURRENCE-ID ersetzen.
    root.children.removeWhere(
      (c) =>
          c is VEvent &&
          c.recurrenceId != null &&
          _sameDay(c.recurrenceId!, recurrenceId),
    );

    final effectiveEnd =
        end ??
        (allDay
            ? start.add(const Duration(days: 1))
            : start.add(const Duration(hours: 1)));

    final override = VEvent(parent: root);
    root.children.add(override);
    override
      ..timeStamp = DateTime.now()
      ..uid = uid
      ..recurrenceId = recurrenceId
      ..summary = summary
      ..start = start
      ..end = effectiveEnd;
    if (description != null && description.isNotEmpty) {
      override.description = description;
    }
    if (location != null && location.isNotEmpty) {
      override.location = location;
    }

    final text = root.toString();
    return allDay ? _toAllDayLines(text) : text;
  }

  /// Wandelt DTSTART/DTEND/RECURRENCE-ID-Zeilen mit Uhrzeit in reine
  /// Datumswerte (VALUE=DATE) um – für Ganztags-Serien.
  String _toAllDayLines(String text) {
    return text.replaceAllMapped(
      RegExp(r'(DTSTART|DTEND|RECURRENCE-ID)[^:\r\n]*:(\d{8})T\d{6}Z?'),
      (m) => '${m.group(1)};VALUE=DATE:${m.group(2)}',
    );
  }

  /// Schließt eine einzelne Serien-Instanz aus: fügt der Serie ein EXDATE für
  /// [occurrenceDate] hinzu und entfernt eine evtl. vorhandene Override-Instanz
  /// (VEVENT mit passender RECURRENCE-ID). Ergebnis ist der neue iCal-Body.
  String excludeOccurrence(
    String rawIcal,
    DateTime occurrenceDate, {
    required bool allDay,
  }) {
    final root = VComponent.parse(rawIcal);

    // Override-Instanz mit passender RECURRENCE-ID entfernen.
    if (root is VCalendar) {
      root.children.removeWhere(
        (c) =>
            c is VEvent &&
            c.recurrenceId != null &&
            _sameDay(c.recurrenceId!, occurrenceDate),
      );
    }

    final components = root is VCalendar ? root.children : [root];
    for (final c in components) {
      if (c is VEvent && c.recurrenceRule != null) {
        final existing =
            c.excludingRecurrenceDates ?? const <DateTimeOrDuration>[];
        final already = existing.any(
          (d) => d.dateTime != null && _sameDay(d.dateTime!, occurrenceDate),
        );
        if (!already) {
          c.excludingRecurrenceDates = [
            ...existing,
            DateTimeOrDuration(occurrenceDate, null),
          ];
        }
        c.timeStamp = DateTime.now();
      }
    }

    var text = root.toString();
    if (allDay) {
      // Ganztags-Serien: EXDATE als reines Datum (VALUE=DATE) schreiben.
      text = text.replaceAllMapped(RegExp(r'EXDATE[^:\r\n]*:([^\r\n]+)'), (m) {
        final values = m
            .group(1)!
            .split(',')
            .map((v) => v.length >= 8 ? v.substring(0, 8) : v)
            .join(',');
        return 'EXDATE;VALUE=DATE:$values';
      });
    }
    return text;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Schreibt DTSTART/DTEND als reine Datumswerte (VALUE=DATE) um – so erkennt
  /// Nextcloud einen echten Ganztags-Termin.
  String _applyAllDay(String text, DateTime start, DateTime end) {
    String d(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}'
        '${x.month.toString().padLeft(2, '0')}'
        '${x.day.toString().padLeft(2, '0')}';
    return text
        .replaceAll(
          RegExp(r'DTSTART[^\r\n]*'),
          'DTSTART;VALUE=DATE:${d(start)}',
        )
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
    String? rrule,
    bool updateRrule = false,
    String? relatedTo,
    bool updateRelated = false,
    int? priority,
    bool updatePriority = false,
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
        if (updatePriority) c.priorityInt = priority;
        c.description = (description == null || description.isEmpty)
            ? null
            : description;
        c.timeStamp = DateTime.now();
      }
    }
    var text = root.toString();
    if (updateRrule) {
      text = _withRruleTodo(_stripRrule(text), rrule);
    }
    if (updateRelated) {
      text = _withRelatedTodo(_stripRelated(text), relatedTo);
    }
    return text;
  }
}
