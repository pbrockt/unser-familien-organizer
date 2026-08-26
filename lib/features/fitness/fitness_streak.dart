import 'fitness_models.dart';

/// Eine Serie erreichter Tagesziele.
class StepStreak {
  const StepStreak({
    required this.current,
    required this.longest,
    required this.startDate,
    required this.lastDate,
    required this.reachedDates,
  });

  /// Länge der laufenden Serie in Tagen.
  final int current;

  /// Längste jemals erreichte Serie.
  final int longest;

  /// Erster Tag der laufenden Serie.
  final String? startDate;

  /// Letzter Tag der laufenden Serie.
  final String? lastDate;

  /// Alle Tage, an denen das Ziel erreicht wurde — für die Markierung im Kalender.
  final Set<String> reachedDates;

  bool get hasStreak => current > 0;

  static const StepStreak leer = StepStreak(
    current: 0,
    longest: 0,
    startDate: null,
    lastDate: null,
    reachedDates: {},
  );
}

/// Berechnet die Serie erreichter Schritteziele.
///
/// „Ohne Unterbrechung" heißt: **aufeinanderfolgende Kalendertage**. Ein Tag ohne Daten
/// unterbricht genauso wie ein Tag unter dem Ziel — sonst würde eine Lücke in der
/// Aufzeichnung die Serie künstlich verlängern.
///
/// Eine Feinheit, die den Unterschied zwischen brauchbar und ärgerlich macht: der
/// **heutige Tag zählt nicht als Unterbrechung**, wenn dafür noch keine Daten vorliegen.
/// Die Tagesdatei wird morgens hochgeladen — ohne diese Ausnahme stünde die Serie den
/// halben Tag lang auf null, obwohl nichts verloren ist.
StepStreak computeStepStreak(
  List<HealthDay> days,
  int goal,
  DateTime today,
) {
  final erreicht = <String>{};
  for (final d in days) {
    final steps = d.steps;
    if (steps != null && steps >= goal) erreicht.add(d.date);
  }
  if (erreicht.isEmpty) return StepStreak.leer;

  final sortiert = erreicht.map(DateTime.parse).toList()..sort();

  // Längste Serie: einmal durchlaufen und Lücken zählen.
  var laengste = 1;
  var lauf = 1;
  for (var i = 1; i < sortiert.length; i++) {
    final abstand = sortiert[i].difference(sortiert[i - 1]).inDays;
    lauf = abstand == 1 ? lauf + 1 : 1;
    if (lauf > laengste) laengste = lauf;
  }

  // Laufende Serie: vom letzten erreichten Tag rückwärts.
  final heute = DateTime(today.year, today.month, today.day);
  final letzter = sortiert.last;
  final tageHer = heute.difference(letzter).inDays;

  // Mehr als ein Tag Abstand heißt: die Serie ist gerissen.
  if (tageHer > 1) {
    return StepStreak(
      current: 0,
      longest: laengste,
      startDate: null,
      lastDate: null,
      reachedDates: erreicht,
    );
  }

  var aktuell = 1;
  var lauf2 = letzter;
  for (var i = sortiert.length - 2; i >= 0; i--) {
    if (lauf2.difference(sortiert[i]).inDays != 1) break;
    aktuell++;
    lauf2 = sortiert[i];
  }

  return StepStreak(
    current: aktuell,
    longest: laengste,
    startDate: _iso(lauf2),
    lastDate: _iso(letzter),
    reachedDates: erreicht,
  );
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
