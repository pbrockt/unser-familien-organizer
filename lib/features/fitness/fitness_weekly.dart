import 'fitness_models.dart';

/// Eine Woche mit den zusammengezählten Minuten auf dem Rad.
class CyclingWeek {
  const CyclingWeek({
    required this.monday,
    required this.minutes,
    required this.km,
    required this.rides,
    required this.isCurrent,
  });

  /// Montag dieser Woche.
  final DateTime monday;
  final int minutes;
  final double km;
  final int rides;

  /// Läuft die Woche noch? Dann ist die Zahl ein Zwischenstand.
  final bool isCurrent;

  DateTime get sunday => monday.add(const Duration(days: 6));
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

/// Zählt Radminuten je Kalenderwoche, neueste zuerst.
///
/// Gezählt wird **jede** Fahrt, auch ein Familienausflug: für ein Bewegungsziel ist Zeit
/// auf dem Rad gleich Zeit auf dem Rad. Die Unterscheidung nach Art der Einheit betrifft
/// nur die Leistungstrends.
///
/// Wochen ohne Fahrt tauchen mit null Minuten auf — eine Lücke einfach wegzulassen würde
/// verschleiern, dass da nichts war, und genau das soll die Liste zeigen.
List<CyclingWeek> cyclingWeeks(
  List<Activity> activities,
  Sport Function(Activity) sportOf,
  DateTime today, {
  int weeks = 6,
}) {
  final heute = DateTime(today.year, today.month, today.day);
  final aktuellerMontag = heute.subtract(Duration(days: heute.weekday - 1));

  final proWoche = <DateTime, List<Activity>>{};
  for (final a in activities) {
    if (sportOf(a) != Sport.cycling) continue;
    final d = DateTime.tryParse(a.date);
    if (d == null) continue;
    final tag = DateTime(d.year, d.month, d.day);
    final montag = tag.subtract(Duration(days: tag.weekday - 1));
    proWoche.putIfAbsent(montag, () => []).add(a);
  }

  return [
    for (var i = 0; i < weeks; i++)
      () {
        final montag = aktuellerMontag.subtract(Duration(days: 7 * i));
        final fahrten = proWoche[montag] ?? const <Activity>[];
        return CyclingWeek(
          monday: montag,
          minutes: (fahrten.fold<int>(0, (s, a) => s + a.durationSec) / 60).round(),
          km: fahrten.fold<double>(0, (s, a) => s + a.distanceKm),
          rides: fahrten.length,
          isCurrent: i == 0,
        );
      }(),
  ];
}
