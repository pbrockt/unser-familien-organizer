import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_analysis.dart';
import 'fitness_charts.dart';
import 'fitness_models.dart';
import 'fitness_providers.dart';
import 'fitness_screen.dart';
import 'fitness_settings.dart';

/// Details eines einzelnen Tages: Gesundheitsdaten und die Einheiten dieses Tages.
class FitnessDayScreen extends ConsumerWidget {
  const FitnessDayScreen({super.key, required this.date});

  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(fitnessDataProvider).value;
    final zones = ref.watch(fitnessZonesProvider);
    final stepGoal = ref.watch(fitnessStepGoalProvider).value ?? 8000;

    final day = data == null
        ? null
        : buildDays(data).where((d) => d.date == date).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(_langDatum(date))),
      body: day == null
          ? const Center(child: Text('Für diesen Tag liegen keine Daten vor.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                if (day.health != null) _HealthCard(day.health!, stepGoal),
                if (day.activities.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'An diesem Tag ist keine Trainingseinheit aufgezeichnet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final a in day.activities) _ActivityCard(a, zones),
              ],
            ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard(this.health, this.stepGoal);

  final HealthDay health;
  final int stepGoal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = health.steps;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tagesdaten', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            if (steps != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$steps Schritte',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Text(
                    steps >= stepGoal ? 'Ziel erreicht' : 'Ziel $stepGoal',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: steps >= stepGoal
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (steps / stepGoal).clamp(0.0, 1.0),
                  minHeight: 7,
                ),
              ),
              const SizedBox(height: 14),
            ],
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                if (health.sleepHours != null)
                  _Wert('Schlaf', '${health.sleepHours!.toStringAsFixed(1)} h'),
                if (health.totalCalories != null)
                  _Wert('Kalorien', '${health.totalCalories}'),
                if (health.activeCalories != null)
                  _Wert('davon aktiv', '${health.activeCalories}'),
                if (health.hrAvg != null) _Wert('Ø Puls', '${health.hrAvg} bpm'),
                if (health.hrMin != null && health.hrMax != null)
                  _Wert('Puls min/max', '${health.hrMin}/${health.hrMax}'),
                if (health.spo2Avg != null) _Wert('SpO₂', '${health.spo2Avg} %'),
                if (health.weightKg != null)
                  _Wert('Gewicht', '${health.weightKg!.toStringAsFixed(1)} kg'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard(this.activity, this.zones);

  final Activity activity;
  final HrZones zones;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sport = activity.sportDetected;
    final istLauf = sport == Sport.running;
    final cadence = Analysis.cadenceCheck(sport, activity.cadenceAvg);
    final zoneSeconds = zones.distribute(activity.hrHistogram);
    final serie = activity.series;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${istLauf ? '🏃' : '🚴'} ${sportLabel(sport)}'
              '${activity.timeOfDay.isEmpty ? '' : ' · ${activity.timeOfDay}'}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _Wert('Distanz', '${activity.distanceKm.toStringAsFixed(2)} km'),
                _Wert('Dauer', Analysis.formatDuration(activity.durationSec)),
                _Wert(
                  istLauf ? 'Pace' : 'Ø Tempo',
                  istLauf
                      ? Analysis.formatPace(activity.paceSecPerKm)
                      : '${activity.speedAvgKmh.toStringAsFixed(1)} km/h',
                ),
                _Wert('Ø Puls', '${activity.hrAvg} bpm'),
                _Wert('Max Puls', '${activity.hrMax} bpm'),
                if (cadence.verdict != Verdict.noData)
                  _Wert(
                    'Ø Kadenz',
                    '${cadence.effectiveValue} ${Analysis.cadenceUnit(sport)}',
                  ),
                if (activity.elevGain > 0)
                  _Wert('Höhenmeter', '${activity.elevGain} hoch'),
                _Wert('Belastung',
                    '${SessionClassifier.loadScore(activity, zones)} P'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Pulszonen', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            _ZoneBar(zoneSeconds: zoneSeconds, labels: zones.labels),
            if (serie.length > 1) ...[
              const SizedBox(height: 18),
              Text('Puls im Verlauf',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              FitnessLineChart(
                points: const [],
                smoothed: [
                  for (final p in serie)
                    if (p.hr > 0) (p.elapsedSec, p.hr.toDouble()),
                ],
                goal: zones.t2.toDouble(),
                height: 140,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Gestrichelt: ${zones.t2} bpm',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZoneBar extends StatelessWidget {
  const _ZoneBar({required this.zoneSeconds, required this.labels});

  final List<int> zoneSeconds;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final total = zoneSeconds.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return Text(
        'Keine Pulsdaten aufgezeichnet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    // Von ruhig nach hart: die Abstufung soll ohne Legende lesbar sein.
    final farben = [
      scheme.primary.withValues(alpha: 0.35),
      scheme.primary,
      scheme.tertiary,
      scheme.error,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  if (zoneSeconds[i] > 0)
                    Expanded(
                      flex: zoneSeconds[i],
                      child: ColoredBox(color: farben[i]),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          children: [
            for (var i = 0; i < 4; i++)
              if (zoneSeconds[i] > 0)
                Text(
                  '${labels[i]}: ${(zoneSeconds[i] * 100 / total).round()} %',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: farben[i]),
                ),
          ],
        ),
      ],
    );
  }
}

class _Wert extends StatelessWidget {
  const _Wert(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

String _langDatum(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const wochentage = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag',
    'Samstag', 'Sonntag'];
  final wt = wochentage[(d.weekday - 1).clamp(0, 6)];
  return '$wt, ${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';
}
