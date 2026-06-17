import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/calendar/calendar_event.dart';
import '../../features/members/member_settings.dart';
import '../../features/tasks/task_item.dart';
import '../../features/weather/weather_service.dart';
import '../platform/platform_support.dart';

/// Aktualisiert die Android-Home-Screen-Widgets (Kalender heute / heute+morgen
/// / Woche / Monat, Aufgaben, Einkauf). Schiebt formatierte Texte in die
/// Widget-Daten und stößt das native Update an.
class HomeWidgets {
  const HomeWidgets._();

  static const _pkg = 'com.pbrockt.family_planner';

  static Future<void> update({
    required List<CalendarEvent> events,
    required List<TaskList> lists,
    Map<String, MemberSetting> memberSettings = const {},
    Map<String, DayWeather> weather = const {},
  }) async {
    if (!isAndroid) return; // Home-Widgets gibt es nur auf Android.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // „Überblick"-Widget: Heute & Morgen (nur Startseiten-Kalender) + Countdown.
    await _pushOverview(
      _overviewBody(events, memberSettings, today, tomorrow),
      _weatherToday(weather, today),
    );

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

  static Future<void> _pushOverview(String body, String weather) async {
    await HomeWidget.saveWidgetData<String>('overview_body', body);
    await HomeWidget.saveWidgetData<String>('overview_weather', weather);
    await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.OverviewWidget');
  }

  // ---- Überblick-Widget ----

  /// Wetter des heutigen Tages als „☀️ 21°" (leer, wenn Wetter aus/unbekannt).
  static String _weatherToday(
      Map<String, DayWeather> weather, DateTime today) {
    if (weather.isEmpty) return '';
    final w = weather[DateFormat('yyyy-MM-dd').format(today)];
    if (w == null) return '';
    return '${weatherEmoji(w.code)} ${w.tempMax.round()}°';
  }

  /// Heute + Morgen (nur Startseiten-Kalender) und Countdown-Termine.
  static String _overviewBody(List<CalendarEvent> events,
      Map<String, MemberSetting> settings, DateTime today, DateTime tomorrow) {
    final home = filterHomeEvents(events, settings);
    final t = _eventsOn(home, today).map(_eventLine).toList();
    final m = _eventsOn(home, tomorrow).map(_eventLine).toList();
    final cd = countdownEvents(events, settings, today);

    final buf = <String>['HEUTE'];
    buf.add(t.isEmpty ? 'Nichts geplant 🎉' : t.take(5).join('\n'));
    buf.add('');
    buf.add('MORGEN');
    buf.add(m.isEmpty ? '–' : m.take(4).join('\n'));

    if (cd.isNotEmpty) {
      buf.add('');
      for (final e in cd.take(3)) {
        final days = e.startDay.difference(today).inDays;
        final label = days == 0
            ? 'heute'
            : days == 1
                ? 'morgen'
                : 'in $days Tagen';
        buf.add('⏳ ${e.summary} · $label');
      }
    }
    return buf.join('\n');
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
