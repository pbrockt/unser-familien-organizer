import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';
import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:family_planner/features/school/school_logic.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent _ev(
  String summary,
  DateTime start, {
  List<String> categories = const [],
}) => CalendarEvent(
  uid: summary,
  summary: summary,
  start: start,
  allDay: true,
  categories: categories,
);

void main() {
  test('buildEvent schreibt CATEGORIES, Parser liest sie', () {
    const b = IcalBuilder();
    final ical = b.buildEvent(
      uid: 'x',
      summary: '📝 Arbeit: Mathe',
      start: DateTime(2026, 7, 6),
      allDay: true,
      categories: const ['Schularbeit', 'Vincent'],
    );
    expect(ical.contains('CATEGORIES:Schularbeit,Vincent'), isTrue);
    final parsed = const IcalParser().parseEvents(ical).first;
    expect(parsed.categories, containsAll(['Schularbeit', 'Vincent']));
  });

  test('isExam / personOf / subjectOf', () {
    final exam = _ev(
      '📝 Arbeit: Mathe',
      DateTime(2026, 7, 6),
      categories: const ['Schularbeit', 'Vincent'],
    );
    expect(isExam(exam), isTrue);
    expect(personOf(exam), 'Vincent');
    expect(subjectOf(exam.summary), 'Mathe');

    final learn = _ev(
      '📚 Lernen: Mathe (2/4)',
      DateTime(2026, 7, 3),
      categories: const ['Lernen', 'Vincent'],
    );
    expect(isStudySession(learn), isTrue);
    expect(subjectOf(learn.summary), 'Mathe');
    expect(personOf(learn), 'Vincent');
  });

  test('groupExamsByPerson: nur zukünftige, alphabetisch, Ohne Person zuletzt', () {
    final today = DateTime(2026, 7, 1);
    final events = [
      _ev('📝 Arbeit: Mathe', DateTime(2026, 7, 6),
          categories: const ['Schularbeit', 'Vincent']),
      _ev('📝 Arbeit: Deutsch', DateTime(2026, 6, 20),
          categories: const ['Schularbeit', 'Vincent']), // Vergangenheit → raus
      _ev('📝 Arbeit: Bio', DateTime(2026, 7, 10),
          categories: const ['Schularbeit', 'Anna']),
      _ev('📝 Arbeit: Kunst', DateTime(2026, 7, 8),
          categories: const ['Schularbeit']), // ohne Person
    ];
    final groups = groupExamsByPerson(events, today);
    expect(groups.map((g) => g.person), ['Anna', 'Vincent', 'Ohne Person']);
    expect(groups.first.exams, hasLength(1)); // Anna: Bio
    // Vincent hat nur die zukünftige Mathe-Arbeit.
    final vincent = groups.firstWhere((g) => g.person == 'Vincent');
    expect(vincent.exams, hasLength(1));
    expect(subjectOf(vincent.exams.first.summary), 'Mathe');
  });

  test('plannedSessions zählt passende Lern-Einheiten', () {
    final now = DateTime(2026, 7, 1, 8);
    final exam = _ev('📝 Arbeit: Mathe', DateTime(2026, 7, 6),
        categories: const ['Schularbeit', 'Vincent']);
    final events = [
      exam,
      _ev('📚 Lernen: Mathe (1/2)', DateTime(2026, 7, 3, 15),
          categories: const ['Lernen', 'Vincent']),
      _ev('📚 Lernen: Mathe (2/2)', DateTime(2026, 7, 5, 15),
          categories: const ['Lernen', 'Vincent']),
      _ev('📚 Lernen: Bio (1/1)', DateTime(2026, 7, 4, 15),
          categories: const ['Lernen', 'Anna']), // andere Person/Fach
    ];
    expect(plannedSessions(events, exam, now), 2);
  });
}
