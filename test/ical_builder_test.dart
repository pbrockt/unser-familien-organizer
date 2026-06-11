import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/caldav/ical_builder.dart';
import 'package:family_planner/core/caldav/ical_parser.dart';

void main() {
  const builder = IcalBuilder();
  const parser = IcalParser();

  test('buildTodo erzeugt ein parsebares, offenes VTODO', () {
    final ical = builder.buildTodo(
      uid: 'u1',
      summary: 'Brot kaufen',
      due: DateTime(2026, 6, 20),
    );
    expect(ical, contains('BEGIN:VTODO'));

    final todos = parser.parseTodos(ical);
    expect(todos, hasLength(1));
    expect(todos.first.summary, 'Brot kaufen');
    expect(todos.first.completed, isFalse);
    expect(todos.first.due, isNotNull);
  });

  test('newUid liefert unterschiedliche IDs', () {
    expect(builder.newUid(), isNot(equals(builder.newUid())));
  });

  test('updateTodo ändert Titel und behält das VTODO gültig', () {
    final original = builder.buildTodo(uid: 'u2', summary: 'Alt');
    final updated = builder.updateTodo(original, summary: 'Neu');

    final todos = parser.parseTodos(updated);
    expect(todos.first.summary, 'Neu');
  });

  test('updateTodo mit clearDue entfernt die Fälligkeit', () {
    final original =
        builder.buildTodo(uid: 'u3', summary: 'X', due: DateTime(2026, 1, 1));
    final cleared =
        builder.updateTodo(original, summary: 'X', clearDue: true);

    final todos = parser.parseTodos(cleared);
    expect(todos.first.due, isNull);
  });
}
