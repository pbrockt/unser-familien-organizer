import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'fitness_providers.dart';
import 'fitness_settings.dart';

/// Kompakte Fitness-Karte für die Startseite: heutige Schritte und die laufende Serie.
///
/// Zeigt sich nur, wenn der Fitness-Bereich aktiviert ist und Daten vorliegen — sonst gäbe
/// es auf der Startseite der ganzen Familie einen leeren Platzhalter.
class FitnessHomeCard extends ConsumerWidget {
  const FitnessHomeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(fitnessEnabledProvider).value ?? false;
    if (!enabled) return const SizedBox.shrink();

    final streak = ref.watch(stepStreakProvider);
    final heute = ref.watch(todayStepsProvider);
    final ziel = ref.watch(fitnessStepGoalProvider).value ?? 8000;
    if (heute == null && !streak.hasStreak) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final erreicht = heute != null && heute >= ziel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go('/fitness'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  erreicht ? '👟' : '🚶',
                  style: const TextStyle(fontSize: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (heute != null) ...[
                        Text(
                          '$heute Schritte heute',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: (heute / ziel).clamp(0.0, 1.0),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 6),
                      ] else
                        Text(
                          'Heutige Schritte noch nicht eingelesen',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      Text(
                        streak.hasStreak
                            ? '🔥 ${streak.current} Tage in Folge über $ziel'
                            : (streak.longest > 0
                                ? 'Serie unterbrochen — Rekord: ${streak.longest} Tage'
                                : 'Noch keine Serie'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: streak.hasStreak
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
