import '../../core/notifications/notification_service.dart';
import '../nutrition/nutrition_models.dart';
import 'fitness_models.dart';
import 'fitness_weekly.dart';
import 'weight_analysis.dart';

/// Feste Notification-ID des Wochenberichts (neben dem Briefing, 900001).
const int kWeeklyReportNotificationId = 900002;

/// Uhrzeit des Berichts am Sonntag.
const int kWeeklyReportHour = 19;

/// Der nächste Sonntag um [kWeeklyReportHour] Uhr — heute, wenn es noch nicht so weit
/// ist.
DateTime nextReportTime(DateTime now) {
  var tag = DateTime(now.year, now.month, now.day, kWeeklyReportHour);
  while (tag.weekday != DateTime.sunday || !tag.isAfter(now)) {
    tag = DateTime(tag.year, tag.month, tag.day + 1, kWeeklyReportHour);
  }
  return tag;
}

/// Text des Berichts für die Woche, die an [sonntag] endet. `null`, wenn es aus der
/// Woche nichts zu berichten gibt — eine Benachrichtigung „keine Daten" hilft niemandem.
///
/// Jede Zahl nur über die Tage, an denen es sie gibt: Ein Tag ohne Schrittdatei ist kein
/// Tag mit null Schritten, ein vergessenes Essen kein Fastentag.
String? weeklyReportBody({
  required DateTime sonntag,
  required List<Activity> activities,
  required Sport Function(Activity) sportOf,
  required List<HealthDay> healthDays,
  required Map<String, NutritionDay> nutrition,
  required List<WeightEntry> weights,
}) {
  final montag = mondayOf(sonntag);
  final tage = {
    for (var i = 0; i < 7; i++) _key(DateTime(montag.year, montag.month, montag.day + i)),
  };

  final schritte = [
    for (final h in healthDays)
      if (tage.contains(h.date) && (h.steps ?? 0) > 0) h.steps!,
  ];
  final rad = cyclingWeekOf(sonntag, activities, sportOf, sonntag);
  final kcal = [
    for (final d in tage)
      if (nutrition[d]?.entries.isNotEmpty ?? false) nutrition[d]!.kcal,
  ];
  final gewicht = weights.isEmpty
      ? null
      : WeightAnalysis.analyse(weights, null, sonntag).ratePerWeek;

  final teile = <String>[
    if (schritte.isNotEmpty)
      'Ø ${_tausender((schritte.reduce((a, b) => a + b) / schritte.length).round())} '
          'Schritte',
    if (rad.minutes > 0)
      '🚲 ${rad.minutes} Min'
          '${rad.rides > 1 ? ' in ${rad.rides} Fahrten' : ''}'
          '${rad.minutes >= weeklyGoalMinutes ? ' ✅' : ' (Ziel $weeklyGoalMinutes)'}',
    if (kcal.isNotEmpty)
      'Ø ${_tausender((kcal.reduce((a, b) => a + b) / kcal.length).round())} kcal',
    if (gewicht != null) 'Gewicht ${_gewicht(gewicht)}/Woche',
  ];
  return teile.isEmpty ? null : teile.join(' · ');
}

/// Plant den Bericht als Benachrichtigung. `null`, wenn ausgeschaltet oder nichts zu
/// berichten ist.
ScheduledReminder? planWeeklyReport({
  required bool enabled,
  required List<Activity> activities,
  required Sport Function(Activity) sportOf,
  required List<HealthDay> healthDays,
  required Map<String, NutritionDay> nutrition,
  required List<WeightEntry> weights,
  DateTime? now,
}) {
  if (!enabled) return null;
  final wann = nextReportTime(now ?? DateTime.now());
  final text = weeklyReportBody(
    sonntag: wann,
    activities: activities,
    sportOf: sportOf,
    healthDays: healthDays,
    nutrition: nutrition,
    weights: weights,
  );
  if (text == null) return null;
  return ScheduledReminder(
    id: kWeeklyReportNotificationId,
    title: 'Deine Woche 💪',
    body: text,
    when: wann,
  );
}

String _key(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// 8432 → 8.432
String _tausender(int v) {
  final s = v.abs().toString();
  final out = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write('.');
    out.write(s[i]);
  }
  return out.toString();
}

/// −0,4 kg / +0,2 kg / ±0 kg
String _gewicht(double kg) {
  final r = (kg * 10).round() / 10;
  if (r == 0) return '±0 kg';
  final betrag = r.abs().toStringAsFixed(1).replaceAll('.', ',');
  return '${r < 0 ? '−' : '+'}$betrag kg';
}
