import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'fitness_models.dart';
import 'fitness_overrides.dart';
import 'fitness_providers.dart';
import 'fitness_settings.dart';
import 'fitness_weekly.dart';

/// Radminuten der laufenden Woche als Ampel — nach links wischbar zu den drei Wochen
/// davor.
///
/// Bewusst eine Karte statt einer Liste: Die Frage „reicht meine Woche?" beantwortet
/// sich am besten mit **einer** großen Zahl. Der Rückblick soll möglich sein, aber nicht
/// dauernd Platz belegen.
class FitnessWeekList extends ConsumerStatefulWidget {
  const FitnessWeekList({super.key});

  @override
  ConsumerState<FitnessWeekList> createState() => _FitnessWeekListState();
}

class _FitnessWeekListState extends ConsumerState<FitnessWeekList> {
  static const _anzahl = 4; // laufende Woche + drei davor

  // Seite 3 ist die laufende Woche: nach links wischen geht in die Vergangenheit,
  // also müssen die älteren Wochen links davon liegen.
  late final PageController _pager =
      PageController(initialPage: _anzahl - 1);
  int _seite = _anzahl - 1;

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

    // cyclingWeeks liefert neueste zuerst; für das Wischen wird umgedreht, damit
    // links „älter" bedeutet.
    final wochen =
        cyclingWeeks(data.activities, sportOf, DateTime.now(), weeks: _anzahl)
            .reversed
            .toList();
    if (wochen.every((w) => w.rides == 0)) return const SizedBox.shrink();

    final dunkel = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 116,
              child: PageView.builder(
                controller: _pager,
                itemCount: wochen.length,
                onPageChanged: (i) => setState(() => _seite = i),
                itemBuilder: (context, i) => _WochenKarte(
                  woche: wochen[i],
                  dunkel: dunkel,
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

class _WochenKarte extends StatelessWidget {
  const _WochenKarte({
    required this.woche,
    required this.dunkel,
    required this.onTap,
  });

  final CyclingWeek woche;
  final bool dunkel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stufe = weeklyLevel(woche.minutes);
    final farbe = _hintergrund(stufe, dunkel);
    final text = _schrift(stufe, dunkel);
    final zeitraum = '${DateFormat('dd.MM.').format(woche.monday)}'
        '–${DateFormat('dd.MM.').format(woche.sunday)}';

    return InkWell(
      onTap: onTap,
      child: Container(
        color: farbe,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    woche.isCurrent ? 'Diese Woche' : zeitraum,
                    style: TextStyle(
                      color: text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _urteil(stufe, woche.isCurrent),
                  style: TextStyle(
                    color: text.withValues(alpha: 0.85),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${woche.minutes}',
                  style: TextStyle(
                    color: text,
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'von 140 min',
                  style: TextStyle(color: text.withValues(alpha: 0.8), fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (woche.minutes / 140).clamp(0.0, 1.0),
                minHeight: 5,
                backgroundColor: text.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation(text.withValues(alpha: 0.75)),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              woche.rides == 0
                  ? 'keine Fahrt'
                  : '${woche.rides} ${woche.rides == 1 ? 'Fahrt' : 'Fahrten'} · '
                      '${woche.km.toStringAsFixed(1)} km',
              style: TextStyle(color: text.withValues(alpha: 0.75), fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  /// Die laufende Woche ist ein Zwischenstand — sie zu bewerten wäre am Montag unfair.
  String _urteil(WeeklyLevel stufe, bool laufend) {
    if (laufend) {
      return switch (stufe) {
        WeeklyLevel.geschafft => 'geschafft 🎉',
        WeeklyLevel.fastGeschafft => 'fast da',
        WeeklyLevel.zuWenig => 'läuft noch',
      };
    }
    return switch (stufe) {
      WeeklyLevel.geschafft => 'geschafft 🎉',
      WeeklyLevel.fastGeschafft => 'knapp dran',
      WeeklyLevel.zuWenig => 'zu wenig',
    };
  }

  /// Gedämpfte Ampelfarben. Kräftige Signalfarben wären auf einer Familien-Startseite
  /// zu laut — und im Dunkelmodus würde es blenden.
  Color _hintergrund(WeeklyLevel stufe, bool dunkel) => switch (stufe) {
        WeeklyLevel.zuWenig =>
          dunkel ? const Color(0xFF43201F) : const Color(0xFFFBE3E0),
        WeeklyLevel.fastGeschafft =>
          dunkel ? const Color(0xFF43391B) : const Color(0xFFFBF1D6),
        WeeklyLevel.geschafft =>
          dunkel ? const Color(0xFF1F3A26) : const Color(0xFFDFF2E3),
      };

  Color _schrift(WeeklyLevel stufe, bool dunkel) {
    if (dunkel) return const Color(0xFFEDEFEA);
    return switch (stufe) {
      WeeklyLevel.zuWenig => const Color(0xFF7A2A22),
      WeeklyLevel.fastGeschafft => const Color(0xFF6B551A),
      WeeklyLevel.geschafft => const Color(0xFF23582F),
    };
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < anzahl; i++)
            Container(
              width: 6,
              height: 6,
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
