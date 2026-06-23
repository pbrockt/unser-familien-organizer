import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const builder = IcalBuilder();
  const parser = IcalParser();

  test('buildTodo mit rrule enthält RRULE vor END:VTODO', () {
    final ical = builder.buildTodo(
      uid: 'x',
      summary: 'Müll rausbringen',
      due: DateTime(2026, 6, 9, 18, 0),
      rrule: 'FREQ=WEEKLY',
    );
    expect(ical.contains('RRULE:FREQ=WEEKLY'), isTrue);
    expect(ical.indexOf('RRULE:'), lessThan(ical.indexOf('END:VTODO')));
  });

  test('updateTodo ersetzt/entfernt RRULE', () {
    final original = builder.buildTodo(
      uid: 'x',
      summary: 'Müll',
      due: DateTime(2026, 6, 9, 18, 0),
      rrule: 'FREQ=WEEKLY',
    );
    final monthly = builder.updateTodo(
      original,
      summary: 'Müll',
      due: DateTime(2026, 6, 9, 18, 0),
      rrule: 'FREQ=MONTHLY',
      updateRrule: true,
    );
    expect(monthly.contains('FREQ=MONTHLY'), isTrue);
    expect(monthly.contains('FREQ=WEEKLY'), isFalse);

    final none = builder.updateTodo(
      original,
      summary: 'Müll',
      due: DateTime(2026, 6, 9, 18, 0),
      rrule: null,
      updateRrule: true,
    );
    expect(none.contains('RRULE:'), isFalse);
  });

  test('advanceRecurringTodo schiebt DUE auf nächstes Vorkommen', () {
    final ical = builder.buildTodo(
      uid: 'x',
      summary: 'Müll',
      due: DateTime(2026, 6, 9, 18, 0), // Dienstag
      rrule: 'FREQ=WEEKLY',
    );
    final advanced = parser.advanceRecurringTodo(ical);
    expect(advanced, isNotNull);
    final todos = parser.parseTodos(advanced!);
    expect(todos, hasLength(1));
    expect(todos.first.due, DateTime(2026, 6, 16, 18, 0));
    expect(todos.first.completed, isFalse);
  });

  test('buildTodo schreibt RELATED-TO; updateTodo ersetzt/entfernt es', () {
    final ical = builder.buildTodo(
      uid: 'x',
      summary: 'Geschenk kaufen',
      relatedTo: 'event-uid-1',
    );
    expect(ical.contains('RELATED-TO:event-uid-1'), isTrue);
    expect(ical.indexOf('RELATED-TO:'), lessThan(ical.indexOf('END:VTODO')));

    final changed = builder.updateTodo(
      ical,
      summary: 'Geschenk kaufen',
      relatedTo: 'event-uid-2',
      updateRelated: true,
    );
    expect(changed.contains('RELATED-TO:event-uid-2'), isTrue);
    expect(changed.contains('event-uid-1'), isFalse);

    final cleared = builder.updateTodo(
      ical,
      summary: 'Geschenk kaufen',
      relatedTo: null,
      updateRelated: true,
    );
    expect(cleared.contains('RELATED-TO:'), isFalse);
  });

  test('advanceRecurringTodo liefert null ohne RRULE', () {
    final ical = builder.buildTodo(
      uid: 'x',
      summary: 'Einmalig',
      due: DateTime(2026, 6, 9, 18, 0),
    );
    expect(parser.advanceRecurringTodo(ical), isNull);
  });
}
