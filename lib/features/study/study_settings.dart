import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lernzeit-Fenster eines Wochentags (Minuten ab Mitternacht).
class StudyWindow {
  const StudyWindow({
    this.enabled = false,
    this.startMinute = 15 * 60,
    this.endMinute = 17 * 60,
  });

  final bool enabled;
  final int startMinute;
  final int endMinute;

  StudyWindow copyWith({bool? enabled, int? startMinute, int? endMinute}) =>
      StudyWindow(
        enabled: enabled ?? this.enabled,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );

  Map<String, dynamic> toJson() => {
    'on': enabled,
    's': startMinute,
    'e': endMinute,
  };

  factory StudyWindow.fromJson(Map<String, dynamic> j) => StudyWindow(
    enabled: (j['on'] as bool?) ?? false,
    startMinute: (j['s'] as int?) ?? 15 * 60,
    endMinute: (j['e'] as int?) ?? 17 * 60,
  );
}

/// 7 Fenster, Index 0 = Montag … 6 = Sonntag (passend zu DateTime.weekday - 1).
/// Standard: Mo–Fr 15:00–17:00 an, Wochenende aus.
List<StudyWindow> defaultStudyWindows() => [
  for (var i = 0; i < 7; i++) StudyWindow(enabled: i < 5),
];

final studyWindowsProvider =
    AsyncNotifierProvider<StudyWindowsController, List<StudyWindow>>(
      StudyWindowsController.new,
    );

class StudyWindowsController extends AsyncNotifier<List<StudyWindow>> {
  static const _key = 'study_windows';

  @override
  Future<List<StudyWindow>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return defaultStudyWindows();
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.length != 7) return defaultStudyWindows();
      return list.map(StudyWindow.fromJson).toList();
    } catch (_) {
      return defaultStudyWindows();
    }
  }

  Future<void> setDay(int weekdayIndex, StudyWindow w) async {
    final cur = List<StudyWindow>.of(state.value ?? defaultStudyWindows());
    cur[weekdayIndex] = w;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(cur.map((e) => e.toJson()).toList()),
    );
    state = AsyncData(cur);
  }
}

/// Href des Kalenders, in den die Lern-Termine angelegt werden.
final studyCalendarHrefProvider =
    AsyncNotifierProvider<StudyCalendarHrefController, String?>(
      StudyCalendarHrefController.new,
    );

class StudyCalendarHrefController extends AsyncNotifier<String?> {
  static const _key = 'study_calendar_href';

  @override
  Future<String?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> set(String? href) async {
    final prefs = await SharedPreferences.getInstance();
    if (href == null || href.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, href);
    }
    state = AsyncData(href);
  }
}
