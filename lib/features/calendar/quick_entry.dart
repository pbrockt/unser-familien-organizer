/// Art des Schnell-Eintrags.
enum QuickKind { event, task, shopping, birthday }

/// Ergebnis der Schnell-Eingabe („Zahnarzt morgen 15 Uhr Arbeit").
class QuickEntry {
  const QuickEntry({
    required this.kind,
    required this.title,
    required this.start,
    required this.allDay,
    this.end,
    this.targetName,
    this.rrule,
    this.reminderMinutes,
    this.saveAsTemplate = false,
    this.location,
    this.birthYear,
  });

  final QuickKind kind;
  final String title;
  final DateTime start;

  /// Ende (aus „14–16 Uhr" / „für 2 Stunden"); nur Termine.
  final DateTime? end;
  final bool allDay;

  /// Erkannter Ziel-Kalender (Termin) oder Ziel-Liste (Aufgabe), sonst `null`.
  final String? targetName;

  /// Wiederholung als RRULE ohne Präfix, z. B. `FREQ=WEEKLY;INTERVAL=2`.
  final String? rrule;

  /// Erinnerung in Minuten vor Beginn.
  final int? reminderMinutes;

  /// Zusätzlich als Vorlage speichern (`vorlage:`).
  final bool saveAsTemplate;

  /// Ort (`@Ort`).
  final String? location;

  /// Geburtsjahr (bei `geburtstag: … 1990`) – fürs Alter.
  final int? birthYear;
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

const _dayparts = {
  'morgens': 8,
  'vormittags': 10,
  'mittags': 12,
  'nachmittags': 15,
  'abends': 19,
  'nachts': 22,
};

/// Wortgrenze, die auch Umlaute berücksichtigt (Dart `\b` basiert nur auf
/// ASCII-`\w`, daher scheitert z. B. „übermorgen").
RegExp _word(String w) =>
    RegExp('(?<![a-zäöüß0-9])$w(?![a-zäöüß0-9])', caseSensitive: false);

String _ymd(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}${two(d.month)}${two(d.day)}';
}

/// Parst eine Freitext-Eingabe in einen strukturierten Schnell-Eintrag.
///
/// Siehe `quick_entry_help.dart` für die unterstützten Befehle.
QuickEntry parseQuickEntry(
  String input,
  DateTime now, {
  List<String> calendarNames = const [],
  List<String> listNames = const [],
}) {
  final today = DateTime(now.year, now.month, now.day);
  var rest = ' ${input.trim()} ';

  void remove(Match m) => rest = rest.replaceRange(m.start, m.end, ' ');
  void removeAll(String pattern) =>
      rest = rest.replaceAll(RegExp(pattern, caseSensitive: false), ' ');

  var kind = QuickKind.event;
  String? targetName;
  var saveAsTemplate = false;

  // --- (a) Typ-/Ziel-Prefix am Zeilenanfang („aufgabe:", „Arbeit:") ---
  final prefix = RegExp(
    r'^\s*([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß0-9 \-]{0,30}?)\s*:\s',
  ).firstMatch(rest);
  if (prefix != null) {
    final word = prefix.group(1)!.trim();
    final lower = word.toLowerCase();
    if (lower == 'aufgabe' || lower == 'todo' || lower == 'aufg') {
      kind = QuickKind.task;
      remove(prefix);
    } else if (lower == 'einkauf' ||
        lower == 'einkaufsliste' ||
        lower == 'einkaufen') {
      kind = QuickKind.shopping;
      remove(prefix);
    } else if (lower == 'geburtstag' || lower == 'geb' || lower == 'bday') {
      kind = QuickKind.birthday;
      remove(prefix);
    } else if (lower == 'vorlage' || lower == 'template') {
      saveAsTemplate = true;
      remove(prefix);
    } else {
      // Ziel-Kalender/Liste nur übernehmen, wenn der Name bekannt ist.
      final known = [
        ...calendarNames,
        ...listNames,
      ].any((n) => n.toLowerCase() == lower);
      if (known) {
        targetName = word;
        remove(prefix);
      }
    }
  }

  // --- (b) Serie ---
  String? freq;
  var interval = 1;
  String? until;
  int? count;
  int? recurWeekday; // bei „jeden montag"

  // „alle 2 wochen" / „alle 3 tage"
  final everyN = RegExp(
    r'\balle\s+(\d+)\s+(tag|tage|woche|wochen|monat|monate|jahr|jahre)\b',
    caseSensitive: false,
  ).firstMatch(rest);
  if (everyN != null) {
    interval = int.tryParse(everyN.group(1)!) ?? 1;
    final u = everyN.group(2)!.toLowerCase();
    freq = u.startsWith('tag')
        ? 'DAILY'
        : u.startsWith('woche')
        ? 'WEEKLY'
        : u.startsWith('monat')
        ? 'MONTHLY'
        : 'YEARLY';
    remove(everyN);
  }
  // „jeden montag"
  if (freq == null) {
    for (final wd in _weekdays.entries) {
      final m = RegExp(
        '\\b(?:jeden|jede)\\s+${wd.key}\\b',
        caseSensitive: false,
      ).firstMatch(rest);
      if (m != null) {
        freq = 'WEEKLY';
        recurWeekday = wd.value;
        remove(m);
        break;
      }
    }
  }
  // Schlüsselwörter
  if (freq == null) {
    if (_word('täglich').hasMatch(rest) ||
        RegExp(r'\bjeden\s+tag\b', caseSensitive: false).hasMatch(rest)) {
      freq = 'DAILY';
      removeAll(r'\btäglich\b|\bjeden\s+tag\b');
    } else if (_word('wöchentlich').hasMatch(rest) ||
        RegExp(r'\bjede\s+woche\b', caseSensitive: false).hasMatch(rest)) {
      freq = 'WEEKLY';
      removeAll(r'\bwöchentlich\b|\bjede\s+woche\b');
    } else if (_word('monatlich').hasMatch(rest) ||
        RegExp(r'\bjeden\s+monat\b', caseSensitive: false).hasMatch(rest)) {
      freq = 'MONTHLY';
      removeAll(r'\bmonatlich\b|\bjeden\s+monat\b');
    } else if (_word('jährlich').hasMatch(rest) ||
        RegExp(r'\bjedes\s+jahr\b', caseSensitive: false).hasMatch(rest)) {
      freq = 'YEARLY';
      removeAll(r'\bjährlich\b|\bjedes\s+jahr\b');
    }
  }
  // Serien-Ende „bis 31.12." (vor allgemeiner Datumserkennung entfernen!)
  if (freq != null) {
    final bis = RegExp(
      r'\bbis\s+(\d{1,2})\.(\d{1,2})\.?(\d{4})?(?!\d)',
      caseSensitive: false,
    ).firstMatch(rest);
    if (bis != null) {
      final dd = int.tryParse(bis.group(1)!);
      final mo = int.tryParse(bis.group(2)!);
      final yy = bis.group(3) != null ? int.tryParse(bis.group(3)!) : null;
      if (dd != null && mo != null && dd <= 31 && mo <= 12) {
        var year = yy ?? today.year;
        var d = DateTime(year, mo, dd);
        if (yy == null && d.isBefore(today)) d = DateTime(year + 1, mo, dd);
        until = _ymd(d);
        remove(bis);
      }
    }
    // „10 mal" / „10x"
    final cnt = RegExp(
      r'\b(\d+)\s*(?:mal|x)\b',
      caseSensitive: false,
    ).firstMatch(rest);
    if (cnt != null) {
      count = int.tryParse(cnt.group(1)!);
      remove(cnt);
    }
  }

  // --- (c) Erinnerung „30 min vorher" / „1 tag vorher" ---
  int? reminderMinutes;
  final rem = RegExp(
    r'\b(?:erinnerung\s+)?(\d+)\s*(minuten?|min|stunden?|std|h|tage?|wochen?)\s*(?:vorher|davor)\b(?:\s*erinnern?)?',
    caseSensitive: false,
  ).firstMatch(rest);
  if (rem != null) {
    final n = int.tryParse(rem.group(1)!) ?? 0;
    final u = rem.group(2)!.toLowerCase();
    reminderMinutes = u.startsWith('min')
        ? n
        : (u.startsWith('std') || u.startsWith('stunde') || u == 'h')
        ? n * 60
        : u.startsWith('tag')
        ? n * 1440
        : n * 10080; // Woche
    remove(rem);
  }

  // --- (d) Ort „@Ort" ---
  String? location;
  final loc = RegExp(r'@(\S+)').firstMatch(rest);
  if (loc != null) {
    location = loc.group(1);
    remove(loc);
  }

  // --- (e) Uhrzeit / Bereich / Dauer / Tageszeit ---
  int? hour;
  int? minute;
  int? endHour;
  int? endMinute;
  int? durationMin;
  var forceAllDay = false;

  if (_word('ganztägig').hasMatch(rest) || _word('ganztags').hasMatch(rest)) {
    forceAllDay = true;
    removeAll(r'\bganztägig\b|\bganztags\b');
  }

  // Bereich „von 14 bis 16 Uhr"
  var range = RegExp(
    r'\b(?:von\s+)?(\d{1,2})(?:[:.](\d{2}))?\s*bis\s*(\d{1,2})(?:[:.](\d{2}))?(?:\s*uhr)?\b',
    caseSensitive: false,
  ).firstMatch(rest);
  // Bereich „14-16 Uhr"
  range ??= RegExp(
    r'\b(\d{1,2})(?:[:.](\d{2}))?\s*[-–]\s*(\d{1,2})(?:[:.](\d{2}))?\s*uhr\b',
    caseSensitive: false,
  ).firstMatch(rest);
  if (range != null) {
    final h1 = int.tryParse(range.group(1)!);
    final h2 = int.tryParse(range.group(3)!);
    if (h1 != null && h1 <= 23 && h2 != null && h2 <= 23) {
      hour = h1;
      minute = range.group(2) != null ? int.tryParse(range.group(2)!) : 0;
      endHour = h2;
      endMinute = range.group(4) != null ? int.tryParse(range.group(4)!) : 0;
      remove(range);
    }
  }

  // Dauer „für 2 Stunden" / „für 90 min"
  if (hour == null || endHour == null) {
    final dur = RegExp(
      r'\bfür\s+(\d+)\s*(stunden?|std|h|minuten?|min)\b',
      caseSensitive: false,
    ).firstMatch(rest);
    if (dur != null) {
      final n = int.tryParse(dur.group(1)!) ?? 0;
      final u = dur.group(2)!.toLowerCase();
      durationMin = u.startsWith('min') ? n : n * 60;
      remove(dur);
    }
  }

  // Einzel-Uhrzeit (nur falls noch kein Bereich)
  if (hour == null) {
    var tm = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(rest);
    tm ??= RegExp(
      r'\b(?:um\s+)?(\d{1,2})(?:[.:](\d{2}))?\s*uhr\b',
      caseSensitive: false,
    ).firstMatch(rest);
    tm ??= RegExp(r'\b(\d{1,2})\s*h\b', caseSensitive: false).firstMatch(rest);
    if (tm != null) {
      final h = int.tryParse(tm.group(1)!);
      final mn = tm.groupCount >= 2 && tm.group(2) != null
          ? int.tryParse(tm.group(2)!)
          : null;
      if (h != null && h <= 23 && (mn == null || mn <= 59)) {
        hour = h;
        minute = mn;
        remove(tm);
      }
    }
  }

  // „halb 4" → 3:30
  if (hour == null) {
    final halb = RegExp(
      r'\bhalb\s+(\d{1,2})\b',
      caseSensitive: false,
    ).firstMatch(rest);
    if (halb != null) {
      final h = int.tryParse(halb.group(1)!);
      if (h != null && h >= 1 && h <= 23) {
        hour = h - 1;
        minute = 30;
        remove(halb);
      }
    }
  }

  // Tageszeiten („nachmittags", „abends") – setzen/verschieben.
  for (final dp in _dayparts.entries) {
    final m = _word(dp.key).firstMatch(rest);
    if (m != null) {
      if (hour == null) {
        hour = dp.value;
        minute = 0;
      } else if (hour < 12 && dp.value >= 12) {
        hour = hour + 12; // „halb 4 nachmittags" → 15:30
      }
      remove(m);
      break;
    }
  }

  // --- (f) Datum ---
  DateTime day = today;
  var dateFound = false;

  // „in 10 Tagen" / „in 2 Wochen" / „in 3 Monaten" / „in einer Woche"
  final relIn = RegExp(
    r'\bin\s+(\d+|einer|einem|einen)\s+(tag|tage|tagen|woche|wochen|monat|monate|monaten)\b',
    caseSensitive: false,
  ).firstMatch(rest);
  if (relIn != null) {
    final numStr = relIn.group(1)!.toLowerCase();
    final n = int.tryParse(numStr) ?? 1;
    final u = relIn.group(2)!.toLowerCase();
    if (u.startsWith('tag')) {
      day = today.add(Duration(days: n));
    } else if (u.startsWith('woche')) {
      day = today.add(Duration(days: 7 * n));
    } else {
      day = DateTime(today.year, today.month + n, today.day);
    }
    dateFound = true;
    remove(relIn);
  }

  // „am Wochenende" → nächster Samstag
  if (!dateFound) {
    final we = RegExp(
      r'\b(?:am\s+)?wochenende\b',
      caseSensitive: false,
    ).firstMatch(rest);
    if (we != null) {
      var d = today;
      while (d.weekday != DateTime.saturday) {
        d = d.add(const Duration(days: 1));
      }
      day = d;
      dateFound = true;
      remove(we);
    }
  }

  // „nächste woche" / „nächsten montag"
  if (!dateFound) {
    final nextWd = RegExp(
      r'\b(?:nächste[nr]?|kommende[nr]?)\s+(montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonnabend|sonntag|woche)\b',
      caseSensitive: false,
    ).firstMatch(rest);
    if (nextWd != null) {
      final w = nextWd.group(1)!.toLowerCase();
      if (w == 'woche') {
        // Montag nächster Woche.
        var d = today.add(const Duration(days: 1));
        while (d.weekday != DateTime.monday) {
          d = d.add(const Duration(days: 1));
        }
        day = d;
      } else {
        final target = _weekdays[w]!;
        var d = today.add(const Duration(days: 1));
        while (d.weekday != target) {
          d = d.add(const Duration(days: 1));
        }
        if (d.difference(today).inDays < 7) d = d.add(const Duration(days: 7));
        day = d;
      }
      dateFound = true;
      remove(nextWd);
    }
  }

  // Relative Tage.
  if (!dateFound) {
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
  }
  // Wochentag (nächstes Vorkommen ab heute) – auch für „jeden montag".
  if (!dateFound) {
    final wd = recurWeekday;
    if (wd != null) {
      var d = today;
      while (d.weekday != wd) {
        d = d.add(const Duration(days: 1));
      }
      day = d;
      dateFound = true;
    }
  }
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
  int? birthYear;
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
        if (yy == null && candidate.isBefore(today)) {
          candidate = DateTime(year + 1, mo, dd);
        }
        // Bei Geburtstagen zählt Tag/Monat; das Jahr ist das Geburtsjahr.
        if (kind == QuickKind.birthday) {
          birthYear = yy;
          var b = DateTime(today.year, mo, dd);
          if (b.isBefore(today)) b = DateTime(today.year + 1, mo, dd);
          candidate = b;
        }
        day = candidate;
        dateFound = true;
        remove(m);
      }
    }
  }

  // --- (g) Ziel-Kalender/Liste als Wort im Satz (falls kein Prefix) ---
  if (targetName == null) {
    final pool = kind == QuickKind.task ? listNames : calendarNames;
    final names = [...pool]..sort((a, b) => b.length.compareTo(a.length));
    for (final name in names) {
      if (name.trim().isEmpty) continue;
      final m = _word(RegExp.escape(name)).firstMatch(rest);
      if (m != null) {
        targetName = name;
        remove(m);
        break;
      }
    }
  }

  // --- (h) Titel = Rest (Füllwörter entfernen) ---
  var title = rest
      .replaceAll(
        RegExp(
          r'\b(am|um|im|in|für|von|bis|jeden|jede|jedes|alle|nächste[nr]?|kommende[nr]?|einer|einem|einen|uhr)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  title = title.replaceAll(RegExp(r'^[\s\-:,]+|[\s\-:,]+$'), '').trim();
  if (kind == QuickKind.birthday && birthYear != null) {
    title = '$title ($birthYear)';
  }

  // --- RRULE bauen ---
  String? rrule;
  if (kind == QuickKind.birthday) {
    rrule = 'FREQ=YEARLY';
  } else if (freq != null) {
    rrule = 'FREQ=$freq';
    if (interval > 1) rrule = '$rrule;INTERVAL=$interval';
    if (until != null) {
      rrule = '$rrule;UNTIL=$until';
    } else if (count != null) {
      rrule = '$rrule;COUNT=$count';
    }
  }

  // --- Start/Ende/allDay ---
  final allDay = kind == QuickKind.birthday || forceAllDay || hour == null;
  final start = allDay
      ? DateTime(day.year, day.month, day.day)
      : DateTime(day.year, day.month, day.day, hour, minute ?? 0);

  DateTime? end;
  if (!allDay) {
    if (endHour != null) {
      end = DateTime(day.year, day.month, day.day, endHour, endMinute ?? 0);
    } else if (durationMin != null) {
      end = start.add(Duration(minutes: durationMin));
    }
  }

  return QuickEntry(
    kind: kind,
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    targetName: targetName,
    rrule: rrule,
    reminderMinutes: reminderMinutes,
    saveAsTemplate: saveAsTemplate,
    location: location,
    birthYear: birthYear,
  );
}
