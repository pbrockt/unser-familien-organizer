import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_event.dart';

/// Woraus Geburtstage erkannt werden.
class BirthdayConfig {
  const BirthdayConfig({this.calendarHref, this.useHeuristic = true});

  /// Ausgewählter Geburtstags-Kalender (href). `null` = keiner gewählt.
  final String? calendarHref;

  /// Zusätzlich anhand des Namens erkennen (z. B. Kontakte-Geburtstage oder
  /// Einträge mit „Geburtstag"/„Birthday").
  final bool useHeuristic;

  /// Ist [e] ein Geburtstag?
  /// - Liegt er im gewählten Geburtstags-Kalender → immer ja (alle Einträge).
  /// - Sonst nur bei aktiver Namens-Erkennung („externe Quellen") und ganztägig.
  bool isBirthday(CalendarEvent e) {
    final href = calendarHref;
    if (href != null && href.isNotEmpty && e.calendarHref == href) return true;
    if (!useHeuristic) return false;
    if (!e.allDay) return false;
    final s = '${e.summary} ${e.calendarName}'.toLowerCase();
    return s.contains('geburtstag') ||
        s.contains('birthday') ||
        s.contains('🎂') ||
        s.contains('👑');
  }

  BirthdayConfig copyWith({
    String? calendarHref,
    bool? useHeuristic,
    bool clearCalendar = false,
  }) => BirthdayConfig(
    calendarHref: clearCalendar ? null : (calendarHref ?? this.calendarHref),
    useHeuristic: useHeuristic ?? this.useHeuristic,
  );
}

/// Kurzform: ist [e] laut [cfg] ein Geburtstag?
bool isBirthday(CalendarEvent e, BirthdayConfig cfg) => cfg.isBirthday(e);

/// Hängt das Alter in eckigen Klammern an, wenn der Titel ein (Geburtsjahr) in
/// runden Klammern enthält – z. B. „Max (1990)" → „Max (1990) [35]" für das
/// Jahr [yearOfOccurrence].
String withBirthdayAge(String summary, int yearOfOccurrence) {
  final m = RegExp(r'\((\d{4})\)').firstMatch(summary);
  if (m == null) return summary;
  final birthYear = int.tryParse(m.group(1)!);
  if (birthYear == null) return summary;
  final age = yearOfOccurrence - birthYear;
  if (age <= 0 || age > 130) return summary;
  return '$summary [$age]';
}

/// Persistierte Geburtstags-Einstellungen.
final birthdayConfigProvider =
    AsyncNotifierProvider<BirthdayConfigController, BirthdayConfig>(
      BirthdayConfigController.new,
    );

class BirthdayConfigController extends AsyncNotifier<BirthdayConfig> {
  static const kCalKey = 'birthday_calendar_href';
  static const kHeurKey = 'birthday_use_heuristic';

  @override
  Future<BirthdayConfig> build() async {
    final p = await SharedPreferences.getInstance();
    final href = p.getString(kCalKey);
    return BirthdayConfig(
      calendarHref: (href == null || href.isEmpty) ? null : href,
      useHeuristic: p.getBool(kHeurKey) ?? true,
    );
  }

  Future<void> setCalendar(String? href) async {
    final p = await SharedPreferences.getInstance();
    final clear = href == null || href.isEmpty;
    if (clear) {
      await p.remove(kCalKey);
    } else {
      await p.setString(kCalKey, href);
    }
    state = AsyncData(
      (state.value ?? const BirthdayConfig()).copyWith(
        calendarHref: href,
        clearCalendar: clear,
      ),
    );
  }

  Future<void> setUseHeuristic(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(kHeurKey, v);
    state = AsyncData(
      (state.value ?? const BirthdayConfig()).copyWith(useHeuristic: v),
    );
  }
}

/// Ein anstehender Geburtstag (nächstes Vorkommen ab heute).
class UpcomingBirthday {
  const UpcomingBirthday(this.event, this.date, this.daysUntil);
  final CalendarEvent event;
  final DateTime date;
  final int daysUntil;
}

/// Anstehende Geburtstage innerhalb von [horizon] Tagen, nach Datum sortiert.
/// Mehrfach-Vorkommen (Serien-Instanzen derselben Person) werden zusammengefasst.
List<UpcomingBirthday> upcomingBirthdays(
  List<CalendarEvent> events,
  DateTime today,
  BirthdayConfig config, {
  int horizon = 60,
}) {
  final seen = <String>{};
  final out = <UpcomingBirthday>[];
  for (final e in events) {
    if (!config.isBirthday(e)) continue;
    final next = _nextOccurrence(e.start, today);
    final days = next.difference(today).inDays;
    if (days < 0 || days > horizon) continue;
    // Pro Person + Tag nur einmal (egal in welchem Jahr die Instanz liegt).
    final key = '${e.summary.toLowerCase()}|${e.start.month}|${e.start.day}';
    if (!seen.add(key)) continue;
    out.add(UpcomingBirthday(e, next, days));
  }
  out.sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
  return out;
}

/// Nächstes Vorkommen von Monat/Tag des Geburtstags ab [today] (heute zählt).
DateTime _nextOccurrence(DateTime birth, DateTime today) {
  var d = DateTime(today.year, birth.month, birth.day);
  if (d.isBefore(today)) d = DateTime(today.year + 1, birth.month, birth.day);
  return d;
}
