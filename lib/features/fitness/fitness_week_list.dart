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
                itemBuilder: (context, i) => _Wochenkachel(
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

class _Wochenkachel extends StatelessWidget {
  const _Wochenkachel({required this.woche, required this.onTap});

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
                          : '${woche.minutes} / $weeklyGoalMinutes min',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _Fortschrittsbalken(
                  tagesMinuten: woche.dailyMinutes,
                  farbe: balken,
                  neutral: neutral,
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
class _Fortschrittsbalken extends StatelessWidget {
  const _Fortschrittsbalken({
    required this.tagesMinuten,
    required this.farbe,
    required this.neutral,
  });

  final List<int> tagesMinuten;
  final Color farbe;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gesamt = tagesMinuten.fold<int>(0, (s, m) => s + m);
    final grund = scheme.onSurface.withValues(alpha: 0.06);

    return LayoutBuilder(
      builder: (context, c) {
        // Über dem Ziel läuft der Balken nicht weiter — dafür gibt es das Sternchen.
        final anteil = (gesamt / weeklyGoalMinutes).clamp(0.0, 1.0);
        final breite = c.maxWidth * anteil;

        return Stack(
          children: [
            Container(
              height: 10,
              decoration: BoxDecoration(
                color: grund,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            if (!neutral && gesamt > 0)
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: SizedBox(
                  height: 10,
                  width: breite,
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        if (tagesMinuten[i] > 0) ...[
                          // Feine Trennlinie zwischen den Fahrtagen.
                          if (_hatVorgaenger(i)) Container(width: 1.5, color: grund),
                          Expanded(
                            flex: tagesMinuten[i],
                            child: ColoredBox(color: farbe),
                          ),
                        ],
                    ],
                  ),
                ),
              ),
            // Zielmarke bei 120 – auch wenn der Balken sie noch nicht erreicht.
            Positioned(
              left: c.maxWidth - 1.5,
              child: Container(width: 1.5, height: 10, color: grund),
            ),
          ],
        );
      },
    );
  }

  bool _hatVorgaenger(int index) {
    for (var i = 0; i < index; i++) {
      if (tagesMinuten[i] > 0) return true;
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
