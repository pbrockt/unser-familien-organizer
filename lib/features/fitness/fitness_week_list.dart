import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'fitness_models.dart';
import 'fitness_overrides.dart';
import 'fitness_providers.dart';
import 'fitness_settings.dart';
import 'fitness_weekly.dart';

/// Radminuten je Woche als Ampel — auf einen Blick erkennbar, wo man steht.
///
/// Die Farbe steckt im Hintergrund der ganzen Zeile, nicht in einem kleinen Punkt: Der
/// Zweck ist, beim Überfliegen der Startseite sofort zu sehen, ob die Woche reicht.
class FitnessWeekList extends ConsumerWidget {
  const FitnessWeekList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(fitnessEnabledProvider).value ?? false;
    if (!enabled) return const SizedBox.shrink();

    final data = ref.watch(fitnessDataProvider).value;
    if (data == null || data.activities.isEmpty) return const SizedBox.shrink();

    final overrides = ref.watch(fitnessOverridesProvider).value;
    Sport sportOf(Activity a) => overrides?.sports[a.id] ?? a.sportDetected;

    final wochen = cyclingWeeks(data.activities, sportOf, DateTime.now());
    if (wochen.every((w) => w.rides == 0)) return const SizedBox.shrink();

    final dunkel = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Radminuten pro Woche',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    'Ziel 140',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            for (final w in wochen)
              _WochenZeile(
                woche: w,
                dunkel: dunkel,
                onTap: () => context.go('/fitness'),
              ),
          ],
        ),
      ),
    );
  }
}

class _WochenZeile extends StatelessWidget {
  const _WochenZeile({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Text(
                '${woche.minutes}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: text,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            Text('min', style: TextStyle(color: text, fontSize: 12)),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  woche.isCurrent ? 'diese Woche' : zeitraum,
                  style: TextStyle(color: text, fontSize: 12.5),
                ),
                Text(
                  woche.rides == 0
                      ? 'keine Fahrt'
                      : '${woche.rides} ${woche.rides == 1 ? 'Fahrt' : 'Fahrten'} · '
                          '${woche.km.toStringAsFixed(1)} km',
                  style: TextStyle(
                    color: text.withValues(alpha: 0.75),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Gedämpfte Ampelfarben. Kräftige Signalfarben wären auf einer Familien-Startseite
  /// zu laut — und im Dunkelmodus geblendet es sonst.
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
