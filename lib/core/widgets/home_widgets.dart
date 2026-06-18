import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../features/calendar/calendar_event.dart';
import '../../features/members/member_settings.dart';
import '../../features/tasks/task_item.dart';
import '../../features/weather/weather_service.dart';
import '../../shared/utils/hex_color.dart';
import '../platform/platform_support.dart';

/// Trenner zwischen Farb-Markierung (#RRGGBB) und Text einer Zeile.
/// Tab ist in der SharedPreferences-XML gültig (anders als z. B. U+001F) und
/// kommt in Termintexten praktisch nicht vor. Die native Seite (FpWidgets.kt)
/// macht daraus einen farbigen Punkt/Balken.
const String _kSep = '\t';

/// Aktualisiert die Android-Home-Screen-Widgets „Anstehende Termine"
/// (Kalender-Stil) und „Countdown".
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
      'next_body',
      _eventsBody(events, now, today),
    );
    await HomeWidget.saveWidgetData<String>(
      'countdown_body',
      _countdownBody(events, memberSettings, today),
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: '$_pkg.NextEventsWidget',
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: '$_pkg.CountdownWidget',
    );
    // Design-Widget nutzt dieselben Termin-Daten (next_body).
    await HomeWidget.updateWidget(qualifiedAndroidName: '$_pkg.DesignWidget');
  }

  /// Anstehende Termine (ab heute, ~2 Wochen), **pro Tag** aufgelöst – mehrtägige
  /// Termine erscheinen an jedem Tag, den sie berühren. Gruppiert mit relativen
  /// Überschriften (HEUTE/MORGEN/Datum).
  static String _eventsBody(
    List<CalendarEvent> events,
    DateTime now,
    DateTime today,
  ) {
    final lines = <String>[];
    for (var d = 0; d <= 13 && lines.length < 12; d++) {
      final day = today.add(Duration(days: d));
      final dayEvents =
          events.where((e) {
            if (!e.occursOn(day)) return false;
            // Heute: bereits vergangene (eintägige) Termine ausblenden.
            if (d == 0 && !e.allDay && !e.isMultiDay && e.hasPassed(now)) {
              return false;
            }
            return true;
          }).toList()..sort((a, b) {
            if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
            return a.start.compareTo(b.start);
          });
      if (dayEvents.isEmpty) continue;
      lines.add(
        d == 0
            ? 'HEUTE'
            : d == 1
            ? 'MORGEN'
            : _fmt('EEE, d. MMM', day).toUpperCase(),
      );
      for (final e in dayEvents) {
        if (lines.length >= 12) break;
        lines.add(_calLine(e));
      }
    }
    return lines.isEmpty ? 'Keine anstehenden Termine 🎉' : lines.join('\n');
  }

  /// Kalender-Eintrags-Stil: Zeitspanne (von–bis); mehrtägige/ganztägige als
  /// „ganztägig".
  static String _calLine(CalendarEvent e) {
    final String when;
    if (e.allDay || e.isMultiDay) {
      when = 'ganztägig';
    } else {
      final end = e.end;
      when = end != null
          ? '${_fmt('HH:mm', e.start)}–${_fmt('HH:mm', end)}'
          : _fmt('HH:mm', e.start);
    }
    return '${_colorHex(e)}$_kSep$when  ${e.summary}';
  }

  /// Countdown-Termine als „Name · noch X Tage".
  static String _countdownBody(
    List<CalendarEvent> events,
    Map<String, MemberSetting> settings,
    DateTime today,
  ) {
    final cds = countdownEvents(events, settings, today);
    if (cds.isEmpty) return 'Keine Countdowns aktiv';
    final lines = <String>[];
    for (final e in cds.take(9)) {
      final days = e.startDay.difference(today).inDays;
      final label = days <= 0
          ? 'heute! 🎉'
          : days == 1
          ? 'morgen'
          : 'noch $days Tage';
      lines.add('${_colorHex(e)}$_kSep${e.summary} · $label');
    }
    return lines.join('\n');
  }

  /// Kalenderfarbe als #RRGGBB (oder gedämpftes Braun, falls keine gesetzt).
  static String _colorHex(CalendarEvent e) =>
      e.color != null ? toHexRgb(e.color!) : '#8C7F73';

  static String _fmt(String pattern, DateTime d) =>
      DateFormat(pattern, 'de_DE').format(d);
}
