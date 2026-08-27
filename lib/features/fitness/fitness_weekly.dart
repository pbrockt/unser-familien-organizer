import '../../shared/utils/week.dart';
import 'fitness_models.dart';

/// Eine Woche mit den zusammengezählten Minuten auf dem Rad.
class CyclingWeek {
  const CyclingWeek({
    required this.monday,
    required this.minutes,
    required this.km,
    required this.rides,
    required this.dailyMinutes,
    required this.isCurrent,
    required this.isFuture,
  });

  /// Montag dieser Woche.
  final DateTime monday;
  final int minutes;
  final double km;
  final int rides;

  /// Minuten je Wochentag, Montag zuerst — immer sieben Einträge.
  final List<int> dailyMinutes;

  /// Läuft die Woche gerade? Dann ist die Zahl ein Zwischenstand.
  final bool isCurrent;

  /// Liegt die Woche noch vor uns?
  final bool isFuture;

  /// Abgeschlossen heißt: vorbei und damit endgültig bewertbar.
  bool get isComplete => !isCurrent && !isFuture;

  DateTime get sunday => monday.add(const Duration(days: 6));

  int get weekNumber => isoWeekNumber(monday);
}

/// Bewertungsstufen für die Wochenminuten.
enum WeeklyLevel { zuWenig, fastGeschafft, geschafft }

/// Ordnet die Minuten einer Stufe zu.
///
/// Die Schwellen sind bewusst frei wählbar: 100 und 140 Minuten sind eine persönliche
/// Leiter, keine medizinische Vorgabe. Sie liegen in der Nähe der verbreiteten Empfehlung
/// von 150 Minuten Bewegung pro Woche, ohne sie eins zu eins zu übernehmen.
WeeklyLevel weeklyLevel(int minutes, {int lower = 100, int upper = 140}) {
  if (minutes < lower) return WeeklyLevel.zuWenig;
  if (minutes <= upper) return WeeklyLevel.fastGeschafft;
  return WeeklyLevel.geschafft;
}

/// Montag der Woche, in der [date] liegt.
DateTime mondayOf(DateTime date) {
  final tag = DateTime(date.year, date.month, date.day);
  return tag.subtract(Duration(days: tag.weekday - 1));
}

/// Zählt Radminuten je Kalenderwoche, **älteste zuerst**.
///
/// Die Reihenfolge ist so gewählt, dass sie sich unverändert in ein Wischfeld legen
/// lässt: links liegt die Vergangenheit, rechts die Zukunft — anders herum wischte man
/// nach links in die Zukunft.
///
/// Gezählt wird **jede** Fahrt, auch ein Familienausflug: für ein Bewegungsziel ist Zeit
/// auf dem Rad gleich Zeit auf dem Rad. Die Unterscheidung nach Art der Einheit betrifft
/// nur die Leistungstrends.
List<CyclingWeek> cyclingWeeks(
  List<Activity> activities,
  Sport Function(Activity) sportOf,
  DateTime today, {
  int weeksBack = 1,
  int weeksForward = 1,
}) {
  final aktuellerMontag = mondayOf(today);

  final proWoche = <DateTime, List<Activity>>{};
  for (final a in activities) {
    if (sportOf(a) != Sport.cycling) continue;
    final d = DateTime.tryParse(a.date);
    if (d == null) continue;
    proWoche.putIfAbsent(mondayOf(d), () => []).add(a);
  }

  return [
    for (var versatz = -weeksBack; versatz <= weeksForward; versatz++)
      _woche(aktuellerMontag, versatz, proWoche),
  ];
}

/// Die Woche, in der [date] liegt — für Einfärbungen an beliebiger Stelle.
CyclingWeek cyclingWeekOf(
  DateTime date,
  List<Activity> activities,
  Sport Function(Activity) sportOf,
  DateTime today,
) {
  final montag = mondayOf(date);
  final proWoche = <DateTime, List<Activity>>{};
  for (final a in activities) {
    if (sportOf(a) != Sport.cycling) continue;
    final d = DateTime.tryParse(a.date);
    if (d == null) continue;
    final m = mondayOf(d);
    if (m == montag) proWoche.putIfAbsent(m, () => []).add(a);
  }
  final versatz = montag.difference(mondayOf(today)).inDays ~/ 7;
  return _woche(mondayOf(today), versatz, proWoche);
}

CyclingWeek _woche(
  DateTime aktuellerMontag,
  int versatz,
  Map<DateTime, List<Activity>> proWoche,
) {
  final montag = aktuellerMontag.add(Duration(days: 7 * versatz));
  final fahrten = proWoche[montag] ?? const <Activity>[];

  final proTag = List<int>.filled(7, 0);
  for (final a in fahrten) {
    final d = DateTime.tryParse(a.date);
    if (d == null) continue;
    final index = (d.weekday - 1).clamp(0, 6);
    proTag[index] += (a.durationSec / 60).round();
  }

  return CyclingWeek(
    monday: montag,
    minutes: proTag.fold<int>(0, (s, m) => s + m),
    km: fahrten.fold<double>(0, (s, a) => s + a.distanceKm),
    rides: fahrten.length,
    dailyMinutes: proTag,
    isCurrent: versatz == 0,
    isFuture: versatz > 0,
  );
}

/// Bewertung je abgeschlossener Woche, für die Einfärbung der Kalenderwochen.
///
/// Nur abgeschlossene Wochen: die laufende ist noch nicht entschieden, und eine
/// künftige erst recht nicht.
Map<DateTime, WeeklyLevel> completedWeekLevels(
  List<Activity> activities,
  Sport Function(Activity) sportOf,
  DateTime today, {
  int lower = 100,
  int upper = 140,
}) {
  final aktuellerMontag = mondayOf(today);
  final proWoche = <DateTime, int>{};

  for (final a in activities) {
    if (sportOf(a) != Sport.cycling) continue;
    final d = DateTime.tryParse(a.date);
    if (d == null) continue;
    final montag = mondayOf(d);
    if (!montag.isBefore(aktuellerMontag)) continue;
    proWoche[montag] = (proWoche[montag] ?? 0) + (a.durationSec / 60).round();
  }

  return {
    for (final e in proWoche.entries)
      e.key: weeklyLevel(e.value, lower: lower, upper: upper),
  };
}
