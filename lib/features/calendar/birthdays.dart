import 'calendar_event.dart';

/// Ist [e] ein Geburtstag? Heuristik (ohne Einstellungen): ganztägig **und**
/// Titel oder Kalendername enthält „geburtstag"/„birthday"/🎂. Deckt u. a. den
/// Nextcloud-Kontakte-Geburtstagskalender ab.
bool isBirthday(CalendarEvent e) {
  if (!e.allDay) return false;
  final s = '${e.summary} ${e.calendarName}'.toLowerCase();
  return s.contains('geburtstag') || s.contains('birthday') || s.contains('🎂');
}

/// Ein anstehender Geburtstag (nächstes Vorkommen ab heute).
class UpcomingBirthday {
  const UpcomingBirthday(this.event, this.date, this.daysUntil);
  final CalendarEvent event;
  final DateTime date;
  final int daysUntil;
}

/// Anstehende Geburtstage innerhalb von [horizon] Tagen, nach Datum sortiert.
/// Mehrfach-Vorkommen (Serien-Instanzen derselben Person) werden zusammengefasst.
List<UpcomingBirthday> upcomingBirthdays(
  List<CalendarEvent> events,
  DateTime today, {
  int horizon = 60,
}) {
  final seen = <String>{};
  final out = <UpcomingBirthday>[];
  for (final e in events) {
    if (!isBirthday(e)) continue;
    final next = _nextOccurrence(e.start, today);
    final days = next.difference(today).inDays;
    if (days < 0 || days > horizon) continue;
    // Pro Person + Tag nur einmal (egal in welchem Jahr die Instanz liegt).
    final key = '${e.summary.toLowerCase()}|${e.start.month}|${e.start.day}';
    if (!seen.add(key)) continue;
    out.add(UpcomingBirthday(e, next, days));
  }
  out.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
  return out;
}

/// Nächstes Vorkommen von Monat/Tag des Geburtstags ab [today] (heute zählt).
DateTime _nextOccurrence(DateTime birth, DateTime today) {
  var d = DateTime(today.year, birth.month, birth.day);
  if (d.isBefore(today)) d = DateTime(today.year + 1, birth.month, birth.day);
  return d;
}
