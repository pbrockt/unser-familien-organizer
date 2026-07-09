import '../calendar/calendar_event.dart';

const String kExamCategory = 'Schularbeit';
const String kStudyCategory = 'Lernen';
const String kDoneCategory = 'Gelernt';
const String kExamPrefix = '📝 Arbeit:';
const String kStudyPrefix = '📚 Lernen:';
const String kNoPerson = 'Ohne Person';

/// Ist [e] eine Schularbeit (per Kategorie oder Titel-Präfix)?
bool isExam(CalendarEvent e) =>
    e.categories.contains(kExamCategory) || e.summary.startsWith(kExamPrefix);

/// Ist [e] eine Lern-Einheit?
bool isStudySession(CalendarEvent e) =>
    e.categories.contains(kStudyCategory) || e.summary.startsWith(kStudyPrefix);

/// Person (Schüler:in) des Eintrags aus den Kategorien; sonst „Ohne Person".
String personOf(CalendarEvent e) {
  for (final c in e.categories) {
    if (c != kExamCategory &&
        c != kStudyCategory &&
        c != kDoneCategory &&
        c.trim().isNotEmpty) {
      return c.trim();
    }
  }
  return kNoPerson;
}

/// Fach/Thema aus dem Titel (Präfix und „(1/4)"-Zusatz entfernt).
String subjectOf(String summary) {
  var s = summary;
  for (final p in const [kExamPrefix, kStudyPrefix]) {
    if (s.startsWith(p)) {
      s = s.substring(p.length);
      break;
    }
  }
  return s.replaceAll(RegExp(r'\s*\(\d+/\d+\)\s*$'), '').trim();
}

/// Ein Personen-Abschnitt mit ihren anstehenden Arbeiten (nach Datum).
class PersonExams {
  const PersonExams(this.person, this.exams);
  final String person;
  final List<CalendarEvent> exams;
}

/// Gruppiert anstehende Arbeiten (ab [today]) nach Person; Personen alphabetisch,
/// „Ohne Person" zuletzt.
List<PersonExams> groupExamsByPerson(
  List<CalendarEvent> events,
  DateTime today,
) {
  final day0 = DateTime(today.year, today.month, today.day);
  final byPerson = <String, List<CalendarEvent>>{};
  for (final e in events) {
    if (!isExam(e)) continue;
    final d = DateTime(e.start.year, e.start.month, e.start.day);
    if (d.isBefore(day0)) continue;
    byPerson.putIfAbsent(personOf(e), () => []).add(e);
  }
  for (final list in byPerson.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  final persons = byPerson.keys.toList()
    ..sort((a, b) {
      if (a == kNoPerson) return 1;
      if (b == kNoPerson) return -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return [for (final p in persons) PersonExams(p, byPerson[p]!)];
}

/// Anzahl noch anstehender Lern-Einheiten zu einer Arbeit (gleiche Person + Fach).
int plannedSessions(
  List<CalendarEvent> events,
  CalendarEvent exam,
  DateTime now,
) {
  final person = personOf(exam);
  final subject = subjectOf(exam.summary).toLowerCase();
  return events
      .where(
        (e) =>
            isStudySession(e) &&
            personOf(e) == person &&
            subjectOf(e.summary).toLowerCase() == subject &&
            e.start.isAfter(now),
      )
      .length;
}

/// Wurde diese Lern-Einheit als „gelernt" abgehakt?
bool isSessionDone(CalendarEvent e) => e.categories.contains(kDoneCategory);

/// Alle Lern-Einheiten zu einer Arbeit (gleiche Person + Fach), nach Datum
/// sortiert – inklusive bereits vergangener, damit man sie abhaken kann.
List<CalendarEvent> studySessionsFor(
  List<CalendarEvent> events,
  CalendarEvent exam,
) {
  final person = personOf(exam);
  final subject = subjectOf(exam.summary).toLowerCase();
  final list = events
      .where(
        (e) =>
            isStudySession(e) &&
            personOf(e) == person &&
            subjectOf(e.summary).toLowerCase() == subject,
      )
      .toList();
  list.sort((a, b) => a.start.compareTo(b.start));
  return list;
}

/// Kategorien einer Lern-Einheit mit oder ohne „Gelernt"-Markierung. Behält die
/// übrigen Kategorien (Typ + Person) unverändert.
List<String> sessionCategoriesToggled(CalendarEvent session, bool done) {
  final cats = session.categories.where((c) => c != kDoneCategory).toList();
  if (done) cats.add(kDoneCategory);
  return cats;
}

/// Darf [username] auf diesem Gerät eine Lern-Einheit von [assignedPerson]
/// abhaken? Eltern-Geräte immer; sonst nur der zugewiesene Nutzer selbst.
/// Ohne Zuweisung (kein/​„Ohne Person") darf jeder abhaken.
bool canCheckStudy({
  required String? assignedPerson,
  required String? username,
  required bool parentMode,
}) {
  if (parentMode) return true;
  if (assignedPerson == null || assignedPerson == kNoPerson) return true;
  return username != null && username == assignedPerson;
}

/// Bearbeiten/Verschieben/Löschen einer Arbeit ist Eltern-Geräten vorbehalten.
bool canEditStudy({required bool parentMode}) => parentMode;
