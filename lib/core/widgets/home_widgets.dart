import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/calendar/calendar_event.dart';
import '../../features/tasks/task_item.dart';

/// Aktualisiert die Android-Home-Screen-Widgets (Kalender heute / heute+morgen
/// / Woche / Monat, Aufgaben, Einkauf). Schiebt formatierte Texte in die
/// Widget-Daten und stößt das native Update an.
class HomeWidgets {
  const HomeWidgets._();

  static const _pkg = 'com.pbrockt.family_planner';

  static Future<void> update({
    required List<CalendarEvent> events,
    required List<TaskList> lists,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    await _push('cal_today', 'CalendarTodayWidget',
        'Heute · ${_fmt('EEE, d. MMM', now)}', _dayBody(events, today));

    await _push('cal_2day', 'CalendarTomorrowWidget', 'Heute & Morgen',
        _twoDayBody(events, today, tomorrow));

    await _push('cal_week', 'CalendarWeekWidget', 'Diese Woche',
        _weekBody(events, today));

    await _push('cal_month', 'CalendarMonthWidget', _fmt('MMMM yyyy', now),
        _monthBody(events, now, today));

    final openTasks = _openTasks(lists);
    await _push('tasks', 'TasksWidget', 'Aufgaben · ${openTasks.length} offen',
        _tasksBody(openTasks));

    final shop = _shoppingList(lists);
    final openShop =
        shop?.items.where((t) => !t.completed).toList() ?? const [];
    await _push('shopping', 'ShoppingWidget',
        'Einkauf · ${openShop.length} offen', _shoppingBody(openShop));
  }

  static Future<void> _push(
      String key, String widget, String title, String body) async {
    await HomeWidget.saveWidgetData<String>('${key}_title', title);
    await HomeWidget.saveWidgetData<String>('${key}_body', body);
    await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.$widget');
  }

  // ---- Formatierung ----

  static String _fmt(String pattern, DateTime d) =>
      DateFormat(pattern, 'de_DE').format(d);

  static List<CalendarEvent> _eventsOn(
      List<CalendarEvent> events, DateTime day) {
    final list = events.where((e) => e.occursOn(day)).toList()
      ..sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.start.compareTo(b.start);
      });
    return list;
  }

  static String _eventLine(CalendarEvent e) {
    final when = e.allDay ? 'Ganztägig' : _fmt('HH:mm', e.start);
    return '$when  ${e.summary}';
  }

  static String _capList(List<String> lines, int max, String empty) {
    if (lines.isEmpty) return empty;
    if (lines.length <= max) return lines.join('\n');
    final shown = lines.take(max).toList();
    shown.add('+ ${lines.length - max} weitere');
    return shown.join('\n');
  }

  static String _dayBody(List<CalendarEvent> events, DateTime day) {
    final lines = _eventsOn(events, day).map(_eventLine).toList();
    return _capList(lines, 7, 'Keine Termine heute 🎉');
  }

  static String _twoDayBody(
      List<CalendarEvent> events, DateTime today, DateTime tomorrow) {
    final t = _eventsOn(events, today).map(_eventLine).toList();
    final m = _eventsOn(events, tomorrow).map(_eventLine).toList();
    final buf = <String>['HEUTE'];
    buf.add(t.isEmpty ? '–' : (t.take(4).join('\n')));
    buf.add('');
    buf.add('MORGEN');
    buf.add(m.isEmpty ? '–' : (m.take(4).join('\n')));
    return buf.join('\n');
  }

  static String _weekBody(List<CalendarEvent> events, DateTime today) {
    final lines = <String>[];
    for (var i = 0; i < 7 && lines.length < 9; i++) {
      final day = today.add(Duration(days: i));
      final dayEvents = _eventsOn(events, day);
      if (dayEvents.isEmpty) continue;
      lines.add(_fmt('EEE d.', day).toUpperCase());
      for (final e in dayEvents) {
        if (lines.length >= 9) break;
        lines.add('  ${_eventLine(e)}');
      }
    }
    return lines.isEmpty ? 'Keine Termine diese Woche' : lines.join('\n');
  }

  static String _monthBody(
      List<CalendarEvent> events, DateTime now, DateTime today) {
    final monthEnd = DateTime(now.year, now.month + 1, 1);
    final inMonth = events
        .where((e) =>
            !e.start.isBefore(today) && e.start.isBefore(monthEnd) && !e.allDay)
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final allDayMonth = events
        .where((e) =>
            e.allDay &&
            !e.endDayInclusive.isBefore(today) &&
            e.startDay.isBefore(monthEnd))
        .length;
    final total = inMonth.length + allDayMonth;
    final lines = <String>['Noch $total Termine diesen Monat'];
    for (final e in inMonth.take(5)) {
      lines.add('${_fmt('d. MMM', e.start)} · ${_fmt('HH:mm', e.start)}  '
          '${e.summary}');
    }
    return lines.join('\n');
  }

  static List<TaskItem> _openTasks(List<TaskList> lists) {
    final items = <TaskItem>[];
    for (final l in lists) {
      items.addAll(l.items.where((t) => !t.completed));
    }
    items.sort((a, b) {
      final ad = a.due, bd = b.due;
      if (ad != null && bd != null) return ad.compareTo(bd);
      if (ad != null) return -1;
      if (bd != null) return 1;
      return a.summary.toLowerCase().compareTo(b.summary.toLowerCase());
    });
    return items;
  }

  static String _tasksBody(List<TaskItem> open) {
    final lines = open.map((t) {
      final due = t.due != null ? ' (bis ${_fmt('d. MMM', t.due!)})' : '';
      return '•  ${t.summary}$due';
    }).toList();
    return _capList(lines, 7, 'Alles erledigt 🎉');
  }

  static TaskList? _shoppingList(List<TaskList> lists) {
    if (lists.isEmpty) return null;
    for (final l in lists) {
      final n = l.name.toLowerCase();
      if (n.contains('einkauf') || n.contains('shopping')) return l;
    }
    return lists.first;
  }

  static String _shoppingBody(List<TaskItem> open) {
    final lines = open.map((t) => '•  ${t.summary}').toList();
    return _capList(lines, 9, 'Liste leer 🎉');
  }
}
