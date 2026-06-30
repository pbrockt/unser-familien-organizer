/// ISO-8601-Kalenderwoche (Woche beginnt Montag; Woche 1 enthält den ersten
/// Donnerstag des Jahres). Liefert 1–53.
int isoWeekNumber(DateTime date) {
  // In UTC rechnen, damit Sommer-/Winterzeit-Wechsel (23-/25-Stunden-Tage) die
  // Tagesdifferenz nicht verfälschen.
  final d = DateTime.utc(date.year, date.month, date.day);
  final dayOfYear = d.difference(DateTime.utc(d.year, 1, 1)).inDays + 1;
  var week = ((dayOfYear - d.weekday + 10) ~/ 7);
  if (week < 1) {
    week = _weeksInYear(d.year - 1);
  } else if (week > _weeksInYear(d.year)) {
    week = 1;
  }
  return week;
}

/// Anzahl ISO-Wochen in einem Jahr (52 oder 53).
int _weeksInYear(int year) {
  int p(int y) => (y + y ~/ 4 - y ~/ 100 + y ~/ 400) % 7;
  return (p(year) == 4 || p(year - 1) == 3) ? 53 : 52;
}
