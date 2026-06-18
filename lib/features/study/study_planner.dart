import 'study_settings.dart';

/// Lernintensität → Anzahl Lern-Tage.
enum StudyIntensity { kurz, mittel, viel }

int studyDaysFor(StudyIntensity i) => switch (i) {
  StudyIntensity.kurz => 2,
  StudyIntensity.mittel => 4,
  StudyIntensity.viel => 7,
};

String studyIntensityLabel(StudyIntensity i) => switch (i) {
  StudyIntensity.kurz => 'kurz',
  StudyIntensity.mittel => 'mittel',
  StudyIntensity.viel => 'viel',
};

/// Eine geplante Lern-Einheit (konkreter Zeitraum).
class StudySession {
  const StudySession(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

/// Plant bis zu [targetDays] Lern-Einheiten an verfügbaren Tagen **vor**
/// [examDay] (exklusiv), rückwärts bis [maxLookbackDays]. Nur Tage mit aktivem
/// Wochentag-Fenster ([windows], Index 0 = Montag). Je Tag eine Einheit, Dauer
/// min(sessionMinutes, Fensterlänge). Nicht vor [notBefore] (Standard: keine
/// Grenze). Ergebnis chronologisch aufsteigend.
List<StudySession> planStudySessions({
  required DateTime examDay,
  required int targetDays,
  required List<StudyWindow> windows,
  int sessionMinutes = 60,
  int maxLookbackDays = 21,
  DateTime? notBefore,
}) {
  final exam = DateTime(examDay.year, examDay.month, examDay.day);
  final floor = notBefore == null
      ? null
      : DateTime(notBefore.year, notBefore.month, notBefore.day);
  final out = <StudySession>[];
  for (
    var back = 1;
    back <= maxLookbackDays && out.length < targetDays;
    back++
  ) {
    final day = exam.subtract(Duration(days: back));
    if (floor != null && day.isBefore(floor)) break;
    if (windows.length != 7) break;
    final w = windows[day.weekday - 1];
    if (!w.enabled || w.endMinute <= w.startMinute) continue;
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      w.startMinute ~/ 60,
      w.startMinute % 60,
    );
    final len = (w.endMinute - w.startMinute).clamp(15, sessionMinutes);
    out.add(StudySession(start, start.add(Duration(minutes: len))));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
