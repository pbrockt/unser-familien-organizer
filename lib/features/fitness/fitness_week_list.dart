import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'fitness_models.dart';
import 'fitness_overrides.dart';
import 'fitness_providers.dart';
import 'fitness_settings.dart';
import 'fitness_weekly.dart';

/// Ampelfarben für die Wochenbewertung, gedämpft.
///
/// Kräftige Signalfarben wären auf einer Familien-Startseite zu laut — und im
/// Dunkelmodus würde es blenden. Dieselben Töne verwendet auch die Kalenderwoche im
/// Kalender, damit man den Zusammenhang erkennt.
class WeeklyColors {
  const WeeklyColors._();

  static Color fill(WeeklyLevel stufe, bool dunkel) => switch (stufe) {
        WeeklyLevel.zuWenig =>
          dunkel ? const Color(0xFF4A2321) : const Color(0xFFF8DAD6),
        WeeklyLevel.fastGeschafft =>
          dunkel ? const Color(0xFF4A3F1D) : const Color(0xFFF8EDCD),
        WeeklyLevel.geschafft =>
          dunkel ? const Color(0xFF22422A) : const Color(0xFFD6EEDC),
      };

  /// Kräftiger Ton für Flächen, die für sich stehen müssen — etwa den
  /// Fortschrittsbalken.
  ///
  /// [fill] ist als Hintergrund gedacht und dafür bewusst blass; als schmaler Balken
  /// auf einer hellen Karte verschwindet er schlicht. Bewusst **nicht** die Akzentfarbe
  /// der App: die ist frei wählbar und würde die Ampel-Aussage rot/gelb/grün auslöschen.
  static Color bar(WeeklyLevel stufe, bool dunkel) => switch (stufe) {
        WeeklyLevel.zuWenig =>
          dunkel ? const Color(0xFFD9705C) : const Color(0xFFC0503F),
        WeeklyLevel.fastGeschafft =>
          dunkel ? const Color(0xFFDDB250) : const Color(0xFFC8992F),
        WeeklyLevel.geschafft =>
          dunkel ? const Color(0xFF63B075) : const Color(0xFF3E8E51),
      };

  static Color ink(WeeklyLevel stufe, bool dunkel) {
    if (dunkel) return const Color(0xFFEDEFEA);
    return switch (stufe) {
      WeeklyLevel.zuWenig => const Color(0xFF7A2A22),
      WeeklyLevel.fastGeschafft => const Color(0xFF6B551A),
      WeeklyLevel.geschafft => const Color(0xFF23582F),
    };
  }
}

/// Radminuten der Woche als Kachel im Überblick — Kalenderwoche und Tages-Kästchen
/// tragen die Farbe, der Rest der Karte bleibt neutral wie die Nachbarkacheln.
///
/// Wischbar: links die vergangene Woche, rechts die kommende.
class FitnessWeekList extends ConsumerStatefulWidget {
  const FitnessWeekList({super.key});

  @override
  ConsumerState<FitnessWeekList> createState() => _FitnessWeekListState();
}

class _FitnessWeekListState extends ConsumerState<FitnessWeekList> {
  // Seite 1 ist die laufende Woche: links davon die vergangene, rechts die kommende.
  static const _startseite = 1;

  late final PageController _pager = PageController(initialPage: _startseite);
  int _seite = _startseite;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(fitnessEnabledProvider).value ?? false;
    if (!enabled) return const SizedBox.shrink();

    final data = ref.watch(fitnessDataProvider).value;
    if (data == null || data.activities.isEmpty) return const SizedBox.shrink();

    final overrides = ref.watch(fitnessOverridesProvider).value;
    Sport sportOf(Activity a) => overrides?.sports[a.id] ?? a.sportEffective;

    final wochen = cyclingWeeks(data.activities, sportOf, DateTime.now());
    if (wochen.every((w) => w.rides == 0)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.08,
              ),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 74,
              child: PageView.builder(
                controller: _pager,
                itemCount: wochen.length,
                onPageChanged: (i) => setState(() => _seite = i),
                itemBuilder: (context, i) => FitnessWeekTile(
                  woche: wochen[i],
                  onTap: () => context.go('/fitness'),
                ),
              ),
            ),
            _Punkte(anzahl: wochen.length, aktiv: _seite),
          ],
        ),
      ),
    );
  }
}

/// Eine Woche als Kachel. Öffentlich, damit sich das Zusammenspiel von Kopfzeile,
/// Kalenderwoche und Balken messen lässt — der Balken allein war schon einmal in
/// Ordnung und trotzdem unsichtbar, weil ihn die Umgebung plattdrückte.
class FitnessWeekTile extends StatelessWidget {
  const FitnessWeekTile({super.key, required this.woche, required this.onTap});

  final CyclingWeek woche;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dunkel = Theme.of(context).brightness == Brightness.dark;
    final stufe = weeklyLevel(woche.minutes);
    final fuellung = WeeklyColors.fill(stufe, dunkel);
    final balken = WeeklyColors.bar(stufe, dunkel);
    final schrift = WeeklyColors.ink(stufe, dunkel);

    // Künftige Wochen sind nicht bewertbar — dort bleibt alles neutral.
    final neutral = woche.isFuture;

    final stern = !neutral && weeklyStar(woche.minutes);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
        children: [
          // Kalenderwoche trägt die Farbe: so ist sie auch nachträglich ablesbar.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: neutral ? scheme.primary.withValues(alpha: 0.10) : fuellung,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'KW',
                    style: TextStyle(
                      fontSize: 8.5,
                      height: 1.1,
                      color: (neutral ? scheme.onSurfaceVariant : schrift)
                          .withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    '${woche.weekNumber}',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      color: neutral ? scheme.onSurfaceVariant : schrift,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _titel(),
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      neutral
                          ? 'geplant'
                          : (woche.rides == 0
                              ? 'noch keine Fahrt'
                              : '${woche.minutes} / $weeklyGoalMinutes min'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FitnessProgressBar(
                  dailyMinutes: woche.dailyMinutes,
                  color: balken,
                  muted: neutral,
                ),
              ],
            ),
          ),
        ],
          ),
          // Sternchen für eine deutlich übertroffene Woche. Oben rechts, damit es
          // nicht mit der Kalenderwoche links konkurriert.
          if (stern)
            const Positioned(
              top: -2,
              right: -2,
              child: Text('⭐', style: TextStyle(fontSize: 15)),
            ),
        ],
      ),
    );
  }

  /// Die Kachel steht im Überblick zwischen Countdowns und Listen — ohne den Zusatz
  /// wäre nicht erkennbar, worauf sich „Diese Woche" bezieht.
  String _titel() {
    if (woche.isCurrent) return 'Fitness · Diese Woche';
    if (woche.isFuture) return 'Fitness · Nächste Woche';
    return 'Fitness · Letzte Woche';
  }
}

/// Balken, der sich von links nach rechts füllt.
///
/// Unterteilt nach Fahrtagen: So ist zu sehen, ob die Minuten aus einer langen Runde
/// stammen oder aus mehreren kurzen — die reine Summe verschweigt das.
/// Balken, der sich von links nach rechts füllt.
///
/// Unterteilt nach Fahrtagen: So ist zu sehen, ob die Minuten aus einer langen Runde
/// stammen oder aus mehreren kurzen — die reine Summe verschweigt das.
///
/// Öffentlich, damit sich die tatsächlich gezeichnete Breite testen lässt. Ein Balken,
/// der aus Layout-Gründen zu null Pixeln zusammenfällt, sieht im Code völlig gesund aus.
class FitnessProgressBar extends StatelessWidget {
  const FitnessProgressBar({
    super.key,
    required this.dailyMinutes,
    required this.color,
    this.goalMinutes = weeklyGoalMinutes,
    this.height = 14,
    this.muted = false,
  });

  final List<int> dailyMinutes;
  final Color color;
  final int goalMinutes;
  final double height;

  /// Künftige Wochen: Rahmen zeigen, aber nichts füllen.
  final bool muted;

  /// Schlüssel des gefüllten Teils — nur fürs Testen.
  static const fillKey = Key('fitness-progress-fill');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gesamt = dailyMinutes.fold<int>(0, (s, m) => s + m);
    // Deutlich sichtbare Spur: Ein leerer Balken muss als leerer Balken erkennbar
    // sein, nicht als fehlender. Bei 10 % Deckkraft war beides nicht zu unterscheiden.
    final grund = scheme.onSurface.withValues(alpha: 0.20);

    // Mindestanteil, damit auch fünf Minuten einen Stummel ergeben statt eines
    // Härchens, das man für nichts hält.
    const mindestens = 0.06;
    final roh = goalMinutes <= 0 ? 0.0 : gesamt / goalMinutes;
    final anteil = gesamt <= 0
        ? 0.0
        : roh.clamp(mindestens, 1.0).toDouble();

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: grund,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
          if (!muted && gesamt > 0)
            // FractionallySizedBox statt selbst gerechneter Breite: die Breite kommt
            // damit aus dem Layout und nicht aus einem LayoutBuilder, dessen
            // Rückgabewert bei ungünstiger Verschachtelung null sein kann.
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: anteil,
                // Ohne heightFactor bestimmt das Kind die Höhe — und eine Row hat von
                // sich aus keine. Der Balken war dadurch zwar korrekt breit, aber null
                // Pixel hoch und damit unsichtbar.
                heightFactor: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(height / 2),
                  child: Row(
                    key: fillKey,
                    children: [
                      for (var i = 0; i < 7; i++)
                        if (dailyMinutes[i] > 0) ...[
                          // Feine Trennlinie zwischen den Fahrtagen.
                          if (_hatVorgaenger(i))
                            SizedBox(width: 1.5, child: ColoredBox(color: grund)),
                          Expanded(
                            flex: dailyMinutes[i],
                            child: ColoredBox(color: color),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _hatVorgaenger(int index) {
    for (var i = 0; i < index; i++) {
      if (dailyMinutes[i] > 0) return true;
    }
    return false;
  }
}

/// Zeigt an, auf welcher Woche man steht — ohne die Wischgeste wäre nicht erkennbar,
/// dass es weitere gibt.
class _Punkte extends StatelessWidget {
  const _Punkte({required this.anzahl, required this.aktiv});

  final int anzahl;
  final int aktiv;

  @override
  Widget build(BuildContext context) {
    final farbe = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < anzahl; i++)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: farbe.withValues(alpha: i == aktiv ? 0.8 : 0.25),
              ),
            ),
        ],
      ),
    );
  }
}
