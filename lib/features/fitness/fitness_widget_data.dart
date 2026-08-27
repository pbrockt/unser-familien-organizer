import 'fitness_models.dart';
import 'fitness_streak.dart';
import 'fitness_weekly.dart';

/// Trenner zwischen Farb-Markierung und Text einer Zeile — muss zu
/// `home_widgets.dart` und `FpWidgets.kt` passen.
const String _sep = '\t';

/// Ampelfarben fürs Widget.
///
/// Eigene, kräftigere Werte als in der App: Auf dem Startbildschirm steht die Zeile
/// allein auf hellem Grund, dort muss die Farbe für sich tragen. Der zarte Ton der
/// App-Kachel wäre dort kaum zu erkennen.
String widgetLevelColor(WeeklyLevel stufe) => switch (stufe) {
      WeeklyLevel.zuWenig => '#C0503F',
      WeeklyLevel.fastGeschafft => '#C8992F',
      WeeklyLevel.geschafft => '#3E8E51',
    };

/// Was das Fitness-Widget anzuzeigen hat.
class FitnessWidgetData {
  const FitnessWidgetData({
    required this.body,
    required this.progressPercent,
    required this.colorHex,
  });

  final String body;

  /// Anteil am Wochenziel in Prozent, 0..100. Über dem Ziel bleibt es bei 100 —
  /// der Balken kann nicht weiter als voll.
  final int progressPercent;

  /// Ampelfarbe des gefüllten Teils.
  final String colorHex;
}

/// Stellt alles zusammen, was das Widget braucht.
FitnessWidgetData buildFitnessWidgetData({
  required List<Activity> activities,
  required Sport Function(Activity) sportOf,
  required List<HealthDay> healthDays,
  required int stepGoal,
  required DateTime today,
}) {
  final diese = cyclingWeeks(activities, sportOf, today,
          weeksBack: 1, weeksForward: 0)
      .last;
  final stufe = weeklyLevel(diese.minutes);
  final anteil = weeklyGoalMinutes <= 0
      ? 0
      : ((diese.minutes / weeklyGoalMinutes) * 100).round().clamp(0, 100);

  return FitnessWidgetData(
    body: buildFitnessWidgetBody(
      activities: activities,
      sportOf: sportOf,
      healthDays: healthDays,
      stepGoal: stepGoal,
      today: today,
    ),
    progressPercent: anteil,
    colorHex: widgetLevelColor(stufe),
  );
}

/// Baut den Text für das Fitness-Widget.
///
/// Bewusst als reine Funktion ohne Android-Bezug: So lässt sich der Inhalt testen,
/// ohne ein Gerät zu bemühen — und genau daran scheitern Widgets sonst still.
///
/// Regeln des Formats, aus den vorhandenen Widgets übernommen:
/// GROSSGESCHRIEBENE Zeilen werden zur Überschrift, Zeilen mit `#RRGGBB` + Tabulator
/// bekommen einen farbigen Marker. Steuerzeichen außer dem Tabulator sind tabu — die
/// Daten landen in einer XML-Datei, die daran zerbricht.
String buildFitnessWidgetBody({
  required List<Activity> activities,
  required Sport Function(Activity) sportOf,
  required List<HealthDay> healthDays,
  required int stepGoal,
  required DateTime today,
}) {
  final wochen = cyclingWeeks(activities, sportOf, today, weeksBack: 1, weeksForward: 0);
  final diese = wochen.last;
  final letzte = wochen.first;

  final stufe = weeklyLevel(diese.minutes);
  final zeilen = <String>[];

  zeilen.add('DIESE WOCHE');
  zeilen.add(
    '${widgetLevelColor(stufe)}$_sep${diese.minutes} von $weeklyGoalMinutes Minuten'
    '${weeklyStar(diese.minutes) ? '  *' : ''}',
  );
  zeilen.add(
    diese.rides == 0
        ? 'noch keine Fahrt'
        : '${diese.rides} ${diese.rides == 1 ? 'Fahrt' : 'Fahrten'} · '
            '${diese.km.toStringAsFixed(1)} km',
  );

  // Die Vorwoche nur zeigen, wenn dort etwas war — sonst nimmt sie bloß Platz weg.
  if (letzte.rides > 0) {
    final letzteStufe = weeklyLevel(letzte.minutes);
    zeilen.add('');
    zeilen.add('LETZTE WOCHE');
    zeilen.add(
      '${widgetLevelColor(letzteStufe)}$_sep${letzte.minutes} Minuten'
      '${weeklyStar(letzte.minutes) ? '  *' : ''}',
    );
  }

  final serie = computeStepStreak(healthDays, stepGoal, today);
  if (serie.hasStreak) {
    zeilen.add('');
    zeilen.add('${serie.current} Tage in Folge über $stepGoal Schritte');
  }

  return zeilen.join('\n');
}
