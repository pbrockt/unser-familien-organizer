import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const b = IcalBuilder();

  test('buildEvent mit rrule enthält RRULE vor END:VEVENT', () {
    final ical = b.buildEvent(
      uid: 'x',
      summary: 'Sport',
      start: DateTime(2026, 6, 20, 18, 0),
      end: DateTime(2026, 6, 20, 19, 0),
      rrule: 'FREQ=WEEKLY',
    );
    expect(ical.contains('RRULE:FREQ=WEEKLY'), isTrue);
    expect(ical.indexOf('RRULE:'), lessThan(ical.indexOf('END:VEVENT')));
  });

  test('ohne rrule keine RRULE-Zeile', () {
    final ical = b.buildEvent(
      uid: 'x',
      summary: 'Einmalig',
      start: DateTime(2026, 6, 20, 18, 0),
    );
    expect(ical.contains('RRULE:'), isFalse);
  });

  test('updateEvent ersetzt vorhandene RRULE', () {
    final original = b.buildEvent(
      uid: 'x',
      summary: 'Sport',
      start: DateTime(2026, 6, 20, 18, 0),
      end: DateTime(2026, 6, 20, 19, 0),
      rrule: 'FREQ=WEEKLY',
    );
    final updated = b.updateEvent(
      original,
      summary: 'Sport',
      start: DateTime(2026, 6, 20, 18, 0),
      end: DateTime(2026, 6, 20, 19, 0),
      rrule: 'FREQ=MONTHLY',
      updateRrule: true,
    );
    expect(updated.contains('FREQ=MONTHLY'), isTrue);
    expect(updated.contains('FREQ=WEEKLY'), isFalse);
  });

  test('updateEvent entfernt RRULE bei rrule=null', () {
    final original = b.buildEvent(
      uid: 'x',
      summary: 'Sport',
      start: DateTime(2026, 6, 20, 18, 0),
      rrule: 'FREQ=WEEKLY',
    );
    final updated = b.updateEvent(
      original,
      summary: 'Sport',
      start: DateTime(2026, 6, 20, 18, 0),
      rrule: null,
      updateRrule: true,
    );
    expect(updated.contains('RRULE:'), isFalse);
  });
}
