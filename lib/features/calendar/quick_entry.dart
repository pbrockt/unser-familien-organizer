/// Ergebnis der Schnell-Eingabe („Zahnarzt morgen 15 Uhr Arbeit").
class QuickEntry {
  const QuickEntry({
    required this.title,
    required this.start,
    required this.allDay,
    this.calendarName,
  });

  final String title;
  final DateTime start;
  final bool allDay;

  /// Erkannter Kalendername aus dem Text (z. B. „Arbeit"), sonst `null`.
  final String? calendarName;
}

const _weekdays = {
  'montag': DateTime.monday,
  'dienstag': DateTime.tuesday,
  'mittwoch': DateTime.wednesday,
  'donnerstag': DateTime.thursday,
  'freitag': DateTime.friday,
  'samstag': DateTime.saturday,
  'sonnabend': DateTime.saturday,
  'sonntag': DateTime.sunday,
};

/// Wortgrenze, die auch Umlaute berücksichtigt (Dart `\b` basiert nur auf
/// ASCII-`\w`, daher scheitert z. B. „übermorgen").
RegExp _word(String w) =>
    RegExp('(?<![a-zäöüß0-9])$w(?![a-zäöüß0-9])', caseSensitive: false);

/// Parst eine Freitext-Eingabe in Titel + Startzeitpunkt.
///
/// Erkennt (deutsch): „heute/morgen/übermorgen", Wochentage, Datum „5.6."/
/// „5.6.2026", sowie Uhrzeiten „15 Uhr", „15:30", „um 15 Uhr", „15h".
/// Ohne Uhrzeit → Ganztags-Termin. Enthält der Text einen der [calendarNames]
/// (als eigenes Wort), wird dieser als Zielkalender erkannt. Der Rest wird zum
/// Titel.
QuickEntry parseQuickEntry(
  String input,
  DateTime now, {
  List<String> calendarNames = const [],
}) {
  final today = DateTime(now.year, now.month, now.day);
  var rest = ' ${input.trim()} ';

  void remove(Match m) => rest = rest.replaceRange(m.start, m.end, ' ');

  DateTime day = today;
  var dateFound = false;
  int? hour;
  int? minute;

  // --- Uhrzeit ---
  // 1) HH:MM
  var tm = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(rest);
  // 2) "um 15 Uhr" / "15.30 Uhr" / "15 Uhr"
  tm ??= RegExp(
    r'\b(?:um\s+)?(\d{1,2})(?:[.:](\d{2}))?\s*uhr\b',
    caseSensitive: false,
  ).firstMatch(rest);
  // 3) "15h"
  tm ??= RegExp(r'\b(\d{1,2})\s*h\b', caseSensitive: false).firstMatch(rest);
  if (tm != null) {
    final h = int.tryParse(tm.group(1)!);
    final mn = tm.groupCount >= 2 && tm.group(2) != null
        ? int.tryParse(tm.group(2)!)
        : null;
    if (h != null &&
        h >= 0 &&
        h <= 23 &&
        (mn == null || (mn >= 0 && mn <= 59))) {
      hour = h;
      minute = mn;
      remove(tm);
    }
  }

  // --- Datum ---
  // Relative Tage.
  for (final entry in const {
    'übermorgen': 2,
    'morgen': 1,
    'heute': 0,
  }.entries) {
    final m = _word(entry.key).firstMatch(rest);
    if (m != null) {
      day = today.add(Duration(days: entry.value));
      dateFound = true;
      remove(m);
      break;
    }
  }
  // Wochentag (nächstes Vorkommen ab heute).
  if (!dateFound) {
    for (final wd in _weekdays.entries) {
      final m = _word(wd.key).firstMatch(rest);
      if (m != null) {
        var d = today;
        while (d.weekday != wd.value) {
          d = d.add(const Duration(days: 1));
        }
        day = d;
        dateFound = true;
        remove(m);
        break;
      }
    }
  }
  // Explizites Datum „5.6." / „5.6.2026".
  if (!dateFound) {
    final m = RegExp(
      r'(?<!\d)(\d{1,2})\.(\d{1,2})\.?(\d{4})?(?!\d)',
    ).firstMatch(rest);
    if (m != null) {
      final dd = int.tryParse(m.group(1)!);
      final mo = int.tryParse(m.group(2)!);
      final yy = m.group(3) != null ? int.tryParse(m.group(3)!) : null;
      if (dd != null &&
          mo != null &&
          dd >= 1 &&
          dd <= 31 &&
          mo >= 1 &&
          mo <= 12) {
        var year = yy ?? today.year;
        var candidate = DateTime(year, mo, dd);
        // Ohne Jahresangabe: liegt das Datum in der Vergangenheit → nächstes Jahr.
        if (yy == null && candidate.isBefore(today)) {
          candidate = DateTime(year + 1, mo, dd);
        }
        day = candidate;
        dateFound = true;
        remove(m);
      }
    }
  }

  // --- Zielkalender (Kalendername als eigenes Wort im Text) ---
  String? calendarName;
  // Längste Namen zuerst, damit z. B. „Arbeit Schmidt" vor „Arbeit" greift.
  final names = [...calendarNames]
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final name in names) {
    if (name.trim().isEmpty) continue;
    final m = _word(RegExp.escape(name)).firstMatch(rest);
    if (m != null) {
      calendarName = name;
      remove(m);
      break;
    }
  }

  // --- Titel aus dem Rest ---
  var title = rest
      .replaceAll(RegExp(r'\b(am|um|im|in)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Bindestriche/Doppelpunkte am Rand entfernen.
  title = title.replaceAll(RegExp(r'^[\s\-:,]+|[\s\-:,]+$'), '').trim();

  final allDay = hour == null;
  final start = allDay
      ? DateTime(day.year, day.month, day.day)
      : DateTime(day.year, day.month, day.day, hour, minute ?? 0);

  return QuickEntry(
    title: title,
    start: start,
    allDay: allDay,
    calendarName: calendarName,
  );
}
