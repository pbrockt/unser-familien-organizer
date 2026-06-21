import 'package:family_planner/features/calendar/birthdays.dart';
import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent _ev({
  bool allDay = true,
  String summary = 'X',
  String cal = 'cal1',
}) => CalendarEvent(
  uid: 'u',
  summary: summary,
  start: DateTime(2026, 6, 20),
  allDay: allDay,
  calendarHref: cal,
);

void main() {
  test('withBirthdayAge berechnet Alter aus (Jahr)', () {
    expect(withBirthdayAge('Max (1990)', 2026), 'Max (1990) [36]');
    expect(withBirthdayAge('Ohne Jahr', 2026), 'Ohne Jahr');
  });

  test('gewählter Kalender → immer Geburtstag (auch ohne Namen/ganztägig)', () {
    const cfg = BirthdayConfig(calendarHref: 'cal1', useHeuristic: false);
    expect(cfg.isBirthday(_ev(cal: 'cal1', allDay: false, summary: 'Egal')),
        isTrue);
    // Heuristik aus → anderer Kalender zählt nicht.
    expect(cfg.isBirthday(_ev(cal: 'cal2', summary: 'Max Geburtstag')), isFalse);
  });

  test('Heuristik an erkennt am Namen (nur ganztägig)', () {
    const cfg = BirthdayConfig(useHeuristic: true);
    expect(cfg.isBirthday(_ev(summary: 'Max Geburtstag')), isTrue);
    expect(cfg.isBirthday(_ev(summary: 'Meeting')), isFalse);
    expect(cfg.isBirthday(_ev(summary: 'Max Geburtstag', allDay: false)),
        isFalse);
  });
}
