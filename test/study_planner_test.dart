import 'package:family_planner/features/study/study_planner.dart';
import 'package:family_planner/features/study/study_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Standard: Mo–Fr 15:00–17:00 an, Sa/So aus.
  final windows = defaultStudyWindows();
  final exam = DateTime(2026, 6, 26); // weit in der Zukunft

  test(
    'plant genau targetDays Einheiten, alle vor der Arbeit & im Fenster',
    () {
      final s = planStudySessions(
        examDay: exam,
        targetDays: 4,
        windows: windows,
        notBefore: exam.subtract(const Duration(days: 60)),
      );
      expect(s.length, 4);
      for (final x in s) {
        expect(x.start.isBefore(exam), isTrue);
        expect(x.start.weekday <= 5, isTrue); // kein Sa/So
        expect(x.start.hour, 15); // Fensterstart
        expect(x.end.difference(x.start).inMinutes, 60);
      }
      // chronologisch aufsteigend
      for (var i = 1; i < s.length; i++) {
        expect(s[i].start.isAfter(s[i - 1].start), isTrue);
      }
    },
  );

  test('überspringt deaktivierte Wochentage (Wochenende)', () {
    final s = planStudySessions(
      examDay: exam,
      targetDays: 5,
      windows: windows,
      notBefore: exam.subtract(const Duration(days: 60)),
    );
    expect(s.length, 5);
    for (final x in s) {
      expect(windows[x.start.weekday - 1].enabled, isTrue);
    }
  });

  test('notBefore begrenzt die Planung', () {
    final s = planStudySessions(
      examDay: exam,
      targetDays: 7,
      windows: windows,
      notBefore: exam.subtract(const Duration(days: 2)),
    );
    // Höchstens die 2 Tage vor der Arbeit (abzüglich evtl. Wochenende).
    expect(s.length <= 2, isTrue);
    for (final x in s) {
      expect(x.start.isBefore(exam.subtract(const Duration(days: 2))), isFalse);
    }
  });
}
