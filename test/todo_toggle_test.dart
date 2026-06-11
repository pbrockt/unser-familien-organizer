import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';

const _sample = '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//FamilyPlanner//test//
BEGIN:VTODO
UID:abc-123
DTSTAMP:20260101T120000Z
SUMMARY:Milch kaufen
STATUS:NEEDS-ACTION
END:VTODO
END:VCALENDAR''';

void main() {
  const parser = IcalParser();

  test('parst ein offenes VTODO', () {
    final todos = parser.parseTodos(_sample);
    expect(todos, hasLength(1));
    expect(todos.first.summary, 'Milch kaufen');
    expect(todos.first.completed, isFalse);
  });

  test('abhaken setzt STATUS:COMPLETED und parst als erledigt', () {
    final updated = parser.toggleTodoCompletion(_sample, completed: true);
    expect(updated, contains('COMPLETED'));

    final todos = parser.parseTodos(updated);
    expect(todos.first.completed, isTrue);
    expect(todos.first.summary, 'Milch kaufen');
  });

  test('wieder-auf-offen setzt zurück auf nicht erledigt', () {
    final done = parser.toggleTodoCompletion(_sample, completed: true);
    final reopened = parser.toggleTodoCompletion(done, completed: false);

    final todos = parser.parseTodos(reopened);
    expect(todos.first.completed, isFalse);
  });
}
