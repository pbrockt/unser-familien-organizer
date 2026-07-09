import 'package:family_planner/features/tasks/task_item.dart';
import 'package:family_planner/features/tasks/tasks_view_providers.dart';
import 'package:flutter_test/flutter_test.dart';

TaskList _list(String href, String name) =>
    TaskList(href: href, name: name, items: const []);

void main() {
  test('isShoppingList: gespeicherte Wahl gewinnt', () {
    final l = _list('/c/a', 'Wocheneinkauf');
    expect(isShoppingList(l, '/c/a'), isTrue);
    expect(isShoppingList(l, '/c/x'), isTrue); // Name enthält „einkauf"
  });

  test('isShoppingList: Namens-Heuristik', () {
    expect(isShoppingList(_list('/c/b', 'Shopping'), null), isTrue);
    expect(isShoppingList(_list('/c/b', 'Einkaufsliste'), null), isTrue);
    expect(isShoppingList(_list('/c/b', 'Hausaufgaben'), null), isFalse);
  });

  test('isShoppingList: Pref-Treffer trotz anderem Namen', () {
    final l = _list('/c/todo', 'Aufgaben');
    expect(isShoppingList(l, '/c/todo'), isTrue);
    expect(isShoppingList(l, null), isFalse);
  });
}
