import '../../core/caldav/caldav_repository.dart';
import '../../core/caldav/ical_parser.dart';
import '../../shared/utils/hex_color.dart';
import '../members/member_settings.dart';
import 'task_item.dart';

const _parser = IcalParser();

/// Sortiert Aufgaben: offene zuerst, dann nach Fälligkeit (ohne Datum ans
/// Ende), dann nach Name.
void sortTaskItems(List<TaskItem> items) {
  items.sort((a, b) {
    if (a.completed != b.completed) return a.completed ? 1 : -1;
    final ad = a.due, bd = b.due;
    if (ad != null && bd != null) {
      final c = ad.compareTo(bd);
      if (c != 0) return c;
    } else if (ad != null) {
      return -1;
    } else if (bd != null) {
      return 1;
    }
    return a.summary.toLowerCase().compareTo(b.summary.toLowerCase());
  });
}

/// Baut aus einem Snapshot die Aufgabenlisten und wendet Mitglieder-
/// Anpassungen (eigene Farbe/Name) an. Reine Funktion ohne Riverpod.
List<TaskList> buildTaskListsFromSnapshot(
  CalDavSnapshot snapshot,
  Map<String, MemberSetting> settings,
) {
  final todoCollections = snapshot.collections.where((c) => c.supportsTodos);
  final lists = <TaskList>[];
  for (final col in todoCollections) {
    final member = settings[col.href];
    final color = parseHexColor(member?.colorHex) ?? parseHexColor(col.color);
    final name = (member?.name != null && member!.name!.isNotEmpty)
        ? member.name!
        : col.displayName;
    final objects = snapshot.objectsOf(col.href);

    final items = <TaskItem>[];
    for (final obj in objects) {
      for (final parsed in _parser.parseTodos(obj.icalData)) {
        items.add(
          TaskItem.fromParsed(
            parsed,
            objectHref: obj.href,
            etag: obj.etag,
            rawIcal: obj.icalData,
            color: color,
          ),
        );
      }
    }
    sortTaskItems(items);
    lists.add(TaskList(href: col.href, name: name, color: color, items: items));
  }
  return lists;
}
