import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:uuid/uuid.dart';

/// Erzeugt und bearbeitet iCalendar-Objekte (VTODO/VEVENT) als vollständige
/// VCALENDAR-Texte zum Schreiben per CalDAV-PUT.
class IcalBuilder {
  const IcalBuilder();

  static const _uuid = Uuid();
  static const _productId = '-//FamilyPlanner//DE';

  /// Neue, eindeutige UID (auch als Dateiname `<uid>.ics` verwendbar).
  String newUid() => _uuid.v4();

  /// Baut ein neues VTODO (offene Aufgabe).
  String buildTodo({
    required String uid,
    required String summary,
    DateTime? due,
    String? description,
  }) {
    final calendar = VCalendar()
      ..version = '2.0'
      ..productId = _productId;
    final todo = VTodo(parent: calendar);
    calendar.children.add(todo);
    todo
      ..timeStamp = DateTime.now()
      ..uid = uid
      ..summary = summary
      ..status = TodoStatus.needsAction;
    if (due != null) todo.due = due;
    if (description != null && description.isNotEmpty) {
      todo.description = description;
    }
    return calendar.toString();
  }

  /// Ändert SUMMARY/DUE/DESCRIPTION eines bestehenden VTODO und behält den
  /// Rest des Objekts erhalten.
  String updateTodo(
    String rawIcal, {
    required String summary,
    DateTime? due,
    bool clearDue = false,
    String? description,
  }) {
    final root = VComponent.parse(rawIcal);
    final components = root is VCalendar ? root.children : [root];
    for (final c in components) {
      if (c is VTodo) {
        c.summary = summary;
        if (clearDue) {
          c.due = null;
        } else if (due != null) {
          c.due = due;
        }
        c.description =
            (description == null || description.isEmpty) ? null : description;
        c.timeStamp = DateTime.now();
      }
    }
    return root.toString();
  }
}
