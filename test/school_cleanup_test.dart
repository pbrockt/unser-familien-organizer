import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:family_planner/features/school/school_logic.dart';
import 'package:family_planner/features/study/study_planner.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent ev({
  required String uid,
  required String summary,
  required List<String> categories,
  DateTime? start,
}) =>
    CalendarEvent(
      uid: uid,
      summary: summary,
      start: start ?? DateTime(2026, 9, 10, 16),
      end: (start ?? DateTime(2026, 9, 10, 16)).add(const Duration(hours: 1)),
      calendarHref: '/cal/',
      categories: categories,
    );

void main() {
  group('Lernintensität', () {
    test('„Ohne" plant keine Lern-Tage', () {
      expect(studyDaysFor(StudyIntensity.ohne), 0);
      expect(studyIntensityLabel(StudyIntensity.ohne), 'ohne Lernen');
    });

    test('die übrigen Stufen bleiben unverändert', () {
      expect(studyDaysFor(StudyIntensity.kurz), 2);
      expect(studyDaysFor(StudyIntensity.mittel), 4);
      expect(studyDaysFor(StudyIntensity.viel), 7);
    });

    test('ohne Lernzeiten kommen keine Einheiten heraus', () {
      final sessions = planStudySessions(
        examDay: DateTime(2026, 9, 20),
        targetDays: 0,
        windows: const [],
        notBefore: DateTime(2026, 9, 1),
      );
      expect(sessions, isEmpty);
    });
  });

  group('Lern-Einheiten einer Arbeit finden', () {
    final arbeit = ev(
      uid: 'exam-1',
      summary: '📝 Arbeit: Mathe',
      categories: ['Schularbeit', 'Lina'],
      start: DateTime(2026, 9, 20),
    );

    final alle = [
      arbeit,
      ev(uid: 's1', summary: '📚 Lernen: Mathe (1/2)', categories: ['Lernen', 'Lina'],
          start: DateTime(2026, 9, 18, 16)),
      ev(uid: 's2', summary: '📚 Lernen: Mathe (2/2)', categories: ['Lernen', 'Lina'],
          start: DateTime(2026, 9, 19, 16)),
      // Andere Person, gleiches Fach — darf nicht mitgelöscht werden.
      ev(uid: 's3', summary: '📚 Lernen: Mathe (1/1)', categories: ['Lernen', 'Ben'],
          start: DateTime(2026, 9, 19, 18)),
      // Gleiche Person, anderes Fach.
      ev(uid: 's4', summary: '📚 Lernen: Deutsch (1/1)', categories: ['Lernen', 'Lina'],
          start: DateTime(2026, 9, 19, 20)),
      // Normaler Termin.
      ev(uid: 'x1', summary: 'Zahnarzt', categories: const []),
    ];

    test('findet nur die Einheiten derselben Person und desselben Fachs', () {
      final treffer = studySessionsFor(alle, arbeit).map((e) => e.uid).toList();
      expect(treffer, ['s1', 's2']);
    });

    test('nimmt auch bereits vergangene Einheiten mit', () {
      // Zum Aufräumen zählt alles, nicht nur Zukünftiges — sonst blieben alte
      // Lern-Termine als Karteileichen im Kalender stehen.
      final vergangen = ev(
        uid: 's0',
        summary: '📚 Lernen: Mathe (0/2)',
        categories: ['Lernen', 'Lina'],
        start: DateTime(2026, 9, 1, 16),
      );
      final treffer =
          studySessionsFor([...alle, vergangen], arbeit).map((e) => e.uid).toList();
      expect(treffer, ['s0', 's1', 's2']);
    });

    test('liefert nichts, wenn es keine Lern-Einheiten gibt', () {
      final ohne = ev(
        uid: 'exam-2',
        summary: '📝 Arbeit: Physik',
        categories: ['Schularbeit', 'Lina'],
      );
      expect(studySessionsFor(alle, ohne), isEmpty);
    });

    test('erkennt eine Arbeit auch ohne Kategorie am Titel', () {
      final nurTitel = ev(uid: 'e3', summary: '📝 Arbeit: Chemie', categories: const []);
      expect(isExam(nurTitel), isTrue);
      expect(isExam(ev(uid: 'e4', summary: 'Elternabend', categories: const [])), isFalse);
    });
  });
}
