import 'calendar_event.dart';

/// Überschneiden sich zwei Zeitspannen (halb-offen: Ende == Start ist kein
/// Konflikt)?
bool timesOverlap(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) => aStart.isBefore(bEnd) && bStart.isBefore(aEnd);

/// Findet bestehende (zeitgebundene) Termine, die sich mit [start]–[end]
/// überschneiden. Ganztägige Termine werden ignoriert; der gerade bearbeitete
/// Termin wird per [ignoreUid]/[ignoreObjectHref] ausgeschlossen.
List<CalendarEvent> findConflicts({
  required List<CalendarEvent> events,
  required DateTime start,
  required DateTime end,
  required bool allDay,
  String? ignoreUid,
  String? ignoreObjectHref,
}) {
  if (allDay) return const [];
  final out = events.where((e) {
    if (e.allDay) return false;
    if (ignoreObjectHref != null &&
        ignoreObjectHref.isNotEmpty &&
        e.objectHref == ignoreObjectHref) {
      return false;
    }
    if (ignoreUid != null && ignoreUid.isNotEmpty && e.uid == ignoreUid) {
      return false;
    }
    final eEnd = e.end ?? e.start.add(const Duration(hours: 1));
    return timesOverlap(start, end, e.start, eEnd);
  }).toList()..sort((a, b) => a.start.compareTo(b.start));
  return out;
}
