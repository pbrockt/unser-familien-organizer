import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/calendar/calendar_event.dart';
import '../../features/members/member_settings.dart';
import '../../features/tasks/task_item.dart';
import '../../features/weather/weather_service.dart';
import '../../shared/utils/hex_color.dart';
import '../platform/platform_support.dart';

/// Trenner zwischen Farb-Markierung und Text einer Termin-Zeile. Die native
/// Widget-Seite (FpWidgets.kt) zeichnet daraus einen farbigen Punkt.
const String _kColorSep = '\u001F';

/// Aktualisiert das Android-Home-Screen-Widget „Anstehende Termine".
/// Schiebt den formatierten Text in die Widget-Daten und stößt das native
/// Update an.
class HomeWidgets {
  const HomeWidgets._();

  static const _pkg = 'com.pbrockt.family_planner';

  static Future<void> update({
    required List<CalendarEvent> events,
    List<TaskList> lists = const [],
    Map<String, MemberSetting> memberSettings = const {},
    Map<String, DayWeather> weather = const {},
  }) async {
    if (!isAndroid) return; // Home-Widgets gibt es nur auf Android.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await HomeWidget.saveWidgetData<String>(
      'upcoming_body',
      _upcomingBody(events, now, today),
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.UpcomingWidget');
  }

  /// Anstehende Termine (ab heute, ~2 Wochen), gruppiert nach Tag mit
  /// relativen Überschriften (HEUTE/MORGEN/Datum) – wie auf der Startseite.
  static String _upcomingBody(
    List<CalendarEvent> events,
    DateTime now,
    DateTime today,
  ) {
    final horizon = today.add(const Duration(days: 14));
    final upcoming = events.where((e) {
      if (e.allDay) {
        return !e.endDayInclusive.isBefore(today) &&
            e.startDay.isBefore(horizon);
      }
      return !e.hasPassed(now) && e.start.isBefore(horizon);
    }).toList()..sort((a, b) => a.start.compareTo(b.start));

    final lines = <String>[];
    String? lastHeader;
    for (final e in upcoming) {
      if (lines.length >= 9) break;
      final d = e.startDay.difference(today).inDays;
      final header = d <= 0
          ? 'HEUTE'
          : d == 1
          ? 'MORGEN'
          : _fmt('EEE, d. MMM', e.start).toUpperCase();
      if (header != lastHeader) {
        lines.add(header);
        lastHeader = header;
      }
      lines.add(_eventLine(e));
    }
    return lines.isEmpty ? 'Keine anstehenden Termine 🎉' : lines.join('\n');
  }

  static String _fmt(String pattern, DateTime d) =>
      DateFormat(pattern, 'de_DE').format(d);

  static String _eventLine(CalendarEvent e) {
    final when = e.allDay ? 'Ganztägig' : _fmt('HH:mm', e.start);
    final line = '$when  ${e.summary}';
    final color = e.color;
    // Farb-Markierung voranstellen → native Seite zeichnet einen farbigen Punkt.
    return color == null ? line : '${toHexRgb(color)}$_kColorSep$line';
  }
}
