import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/calendar/calendar_event.dart';
import '../../features/members/member_settings.dart';
import '../../features/tasks/task_item.dart';
import '../../features/weather/weather_service.dart';
import '../../shared/utils/hex_color.dart';
import '../platform/platform_support.dart';

/// Trenner zwischen Farb-Markierung (#RRGGBB) und Text einer Termin-Zeile.
/// Tab ist in der SharedPreferences-XML gültig (anders als z. B. U+001F) und
/// kommt in Termintexten praktisch nicht vor. Die native Seite (FpWidgets.kt)
/// macht daraus einen farbigen Punkt/Balken.
const String _kSep = '\t';

/// Aktualisiert die Android-Home-Screen-Widgets „Anstehende Termine" und
/// „Nächste Termine". Speichert formatierten Text und stößt das native Update an.
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
      _groupedBody(events, now, today, _homeLine),
    );
    await HomeWidget.saveWidgetData<String>(
      'next_body',
      _groupedBody(events, now, today, _calLine),
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.UpcomingWidget');
    await HomeWidget.updateWidget(
      qualifiedAndroidName: '$_pkg.NextEventsWidget',
    );
  }

  /// Anstehende Termine (ab heute, ~2 Wochen), gruppiert nach Tag mit relativen
  /// Überschriften (HEUTE/MORGEN/Datum). [lineFn] formatiert eine Termin-Zeile.
  static String _groupedBody(
    List<CalendarEvent> events,
    DateTime now,
    DateTime today,
    String Function(CalendarEvent) lineFn,
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
      lines.add(lineFn(e));
    }
    return lines.isEmpty ? 'Keine anstehenden Termine 🎉' : lines.join('\n');
  }

  /// Kalenderfarbe als #RRGGBB (oder gedämpftes Braun, falls keine gesetzt).
  static String _colorHex(CalendarEvent e) =>
      e.color != null ? toHexRgb(e.color!) : '#8C7F73';

  /// Startseiten-Stil: nur Startzeit.
  static String _homeLine(CalendarEvent e) {
    final when = e.allDay ? 'Ganztägig' : _fmt('HH:mm', e.start);
    return '${_colorHex(e)}$_kSep$when  ${e.summary}';
  }

  /// Kalender-Eintrags-Stil: Zeitspanne (von–bis), wie im Reiter Kalender.
  static String _calLine(CalendarEvent e) {
    final String when;
    if (e.allDay) {
      when = 'Ganztägig';
    } else {
      final end = e.end;
      when = end != null
          ? '${_fmt('HH:mm', e.start)}–${_fmt('HH:mm', end)}'
          : _fmt('HH:mm', e.start);
    }
    return '${_colorHex(e)}$_kSep$when  ${e.summary}';
  }

  static String _fmt(String pattern, DateTime d) =>
      DateFormat(pattern, 'de_DE').format(d);
}
