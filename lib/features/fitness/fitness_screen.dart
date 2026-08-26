import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'fitness_analysis.dart';
import 'fitness_charts.dart';
import 'fitness_models.dart';
import 'fitness_providers.dart';
import 'fitness_repository.dart';
import 'fitness_settings.dart';
import 'fitness_widgets.dart';
import 'fitness_training_tab.dart';
import 'fitness_weight_tab.dart';

/// Ein Tag mit allem, was an ihm passiert ist.
class FitnessDay {
  const FitnessDay({
    required this.date,
    required this.health,
    required this.activities,
  });

  final String date;
  final HealthDay? health;
  final List<Activity> activities;
}

/// Führt Gesundheitsdaten und Einheiten zu Tagen zusammen, neueste zuerst.
List<FitnessDay> buildDays(FitnessData data) {
  final dates = <String>{
    ...data.activities.map((a) => a.date),
    ...data.healthDays.map((h) => h.date),
  }.toList()
    ..sort((a, b) => b.compareTo(a));

  final healthByDate = {for (final h in data.healthDays) h.date: h};
  final actByDate = <String, List<Activity>>{};
  for (final a in data.activities) {
    actByDate.putIfAbsent(a.date, () => []).add(a);
  }

  return dates
      .map((d) => FitnessDay(
            date: d,
            health: healthByDate[d],
            activities: actByDate[d] ?? const [],
          ))
      .toList();
}

class FitnessScreen extends ConsumerWidget {
  const FitnessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(fitnessDataProvider);
    final stepGoal = ref.watch(fitnessStepGoalProvider).value ?? 8000;
    final folder = ref.watch(fitnessFolderProvider).value ?? '';
    final syncing = ref.watch(fitnessSyncingProvider);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Fitness'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Übersicht'),
            Tab(text: 'Training'),
            Tab(text: 'Gewicht'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Jetzt abgleichen',
            onPressed: syncing
                ? null
                : () => ref.read(fitnessDataProvider.notifier).sync(),
            icon: syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Einstellungen',
            onPressed: () => context.go('/home/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Hinweis('Die Daten konnten nicht geladen werden: $e'),
        data: (data) {
          if (folder.isEmpty) {
            return const _Hinweis(
              'Noch kein Datenordner gewählt. In den Einstellungen unter „Fitness" den Ordner '
              'in deiner Nextcloud auswählen, in dem die Trainings- und Gesundheitsdateien '
              'liegen.',
            );
          }

          final days = buildDays(data);
          if (days.isEmpty) {
            return const _Hinweis(
              'Im gewählten Ordner wurden noch keine auswertbaren Dateien gefunden. '
              'Erwartet werden .csv-Trainings und .md-Tagesdaten.',
            );
          }

          return TabBarView(
            children: [
              RefreshIndicator(
            onRefresh: () => ref.read(fitnessDataProvider.notifier).sync(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _StepsCard(days: days, goal: stepGoal),
                const SizedBox(height: 12),
                _SleepCard(days: days),
                _RuhepulsCard(days: days),
                const SizedBox(height: 20),
                Text(
                  'Tage',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final day in days.take(120))
                  _DayTile(
                    day: day,
                    onTap: () => context.go('/fitness/tag/${day.date}'),
                  ),
              ],
            ),
              ),
              FitnessTrainingTab(data: data),
              const FitnessWeightTab(),
            ],
          );
        },
      ),
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.days, required this.goal});

  final List<FitnessDay> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    // Älteste links: ein Verlauf liest sich von links nach rechts.
    final withSteps = days.reversed
        .where((d) => d.health?.steps != null)
        .toList();
    if (withSteps.length < 2) return const SizedBox.shrink();

    final recent = withSteps.length > 30
        ? withSteps.sublist(withSteps.length - 30)
        : withSteps;
    final erreicht = recent.where((d) => (d.health!.steps ?? 0) >= goal).length;

    // Steht für heute noch nichts fest, kommt ein gestrichelter Platzhalter ans Ende.
    // Sonst wirkt der letzte gefüllte Balken wie „heute" — und ein guter Tag von
    // vorgestern sieht aus wie gestern.
    final now = DateTime.now();
    final heute = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final heuteFehlt = !recent.any((d) => d.date == heute);

    return _Card(
      title: 'Schritte pro Tag',
      subtitle: '$erreicht von ${recent.length} Tagen über $goal'
          '${heuteFehlt ? ' · heute noch offen' : ''}',
      child: FitnessBarChart(
        values: [
          for (final d in recent)
            ChartValue(_kurzDatum(d.date), (d.health!.steps ?? 0).toDouble()),
          if (heuteFehlt)
            ChartValue(_kurzDatum(heute), goal.toDouble(), pending: true),
        ],
        goal: goal.toDouble(),
      ),
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.days});

  final List<FitnessDay> days;

  @override
  Widget build(BuildContext context) {
    final withSleep = days.reversed
        .where((d) => d.health?.sleepHours != null && d.health!.sleepHours! > 0)
        .toList();
    if (withSleep.length < 2) return const SizedBox.shrink();

    final recent =
        withSleep.length > 30 ? withSleep.sublist(withSleep.length - 30) : withSleep;
    final schnitt = recent
            .map((d) => d.health!.sleepHours!)
            .reduce((a, b) => a + b) /
        recent.length;

    return FitnessExpandableCard(
      title: 'Schlaf pro Nacht',
      subtitle: 'Ø ${schnitt.toStringAsFixed(1)} h · Ziellinie bei 7 h',
      child: FitnessBarChart(
        values: [
          for (final d in recent)
            ChartValue(_kurzDatum(d.date), d.health!.sleepHours!),
        ],
        goal: 7,
      ),
    );
  }
}

/// Ruhepuls-Verlauf — das ehrlichste Fitness-Signal in diesen Daten.
class _RuhepulsCard extends StatelessWidget {
  const _RuhepulsCard({required this.days});

  final List<FitnessDay> days;

  @override
  Widget build(BuildContext context) {
    final trend = analyseRestingHr([
      for (final d in days)
        if (d.health != null) d.health!,
    ]);
    if (!trend.hasData) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final veraenderung = trend.change;

    final String bewertung;
    final Color farbe;
    if (veraenderung == null) {
      bewertung = 'Ab etwa zwei Monaten regelmäßiger Daten wird die Veränderung '
          'aussagekräftig.';
      farbe = scheme.onSurfaceVariant;
    } else if (veraenderung <= -2) {
      bewertung = 'Um $veraenderung bpm gesunken — das deutlichste Zeichen für '
          'bessere Ausdauer, und es lässt sich nicht vortäuschen.';
      farbe = scheme.primary;
    } else if (veraenderung >= 3) {
      bewertung = 'Um +$veraenderung bpm gestiegen. Häufige Gründe: zu wenig Schlaf, '
          'ein Infekt im Anmarsch oder zu viel Belastung ohne Erholung.';
      farbe = scheme.error;
    } else {
      bewertung = 'Weitgehend unverändert gegenüber dem Monat davor.';
      farbe = scheme.onSurfaceVariant;
    }

    return FitnessExpandableCard(
      title: 'Ruhepuls',
      subtitle: trend.avg30 == null
          ? null
          : 'Ø ${trend.avg30} bpm im letzten Monat'
              '${trend.lowest != null ? ' · niedrigster ${trend.lowest}' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FitnessLineChart(smoothed: trend.series, height: 130),
          const SizedBox(height: 10),
          Text(
            bewertung,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: farbe),
          ),
        ],
      ),
    );
  }
}

class _DayTile extends ConsumerWidget {
  const _DayTile({required this.day, required this.onTap});

  final FitnessDay day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(fitnessZonesProvider);
    final scheme = Theme.of(context).colorScheme;
    final h = day.health;

    final teile = <String>[
      if (h?.steps != null) '${h!.steps} Schritte',
      if (h?.sleepHours != null) '${h!.sleepHours!.toStringAsFixed(1)} h Schlaf',
      if (h?.totalCalories != null) '${h!.totalCalories} kcal',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _langDatum(day.date),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (teile.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          teile.join(' · '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    for (final a in day.activities)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${a.sportDetected == Sport.running ? '🏃' : '🚴'} '
                          '${a.distanceKm.toStringAsFixed(1)} km · '
                          '${Analysis.formatDuration(a.durationSec)} · '
                          'Ø ${a.hrAvg} bpm',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: a.hrAvg >= zones.t2
                                    ? scheme.error
                                    : scheme.primary,
                              ),
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
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Hinweis extends StatelessWidget {
  const _Hinweis(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

String _kurzDatum(String iso) =>
    iso.length >= 10 ? '${iso.substring(8, 10)}.${iso.substring(5, 7)}' : iso;

String _langDatum(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const wochentage = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
  final wt = wochentage[(d.weekday - 1).clamp(0, 6)];
  return '$wt, ${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';
}
