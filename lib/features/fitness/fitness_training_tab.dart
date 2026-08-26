import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'fitness_analysis.dart';
import 'fitness_charts.dart';
import 'fitness_models.dart';
import 'fitness_overrides.dart';
import 'fitness_repository.dart';
import 'fitness_settings.dart';
import 'fitness_widgets.dart';

/// Auswertung über alle Einheiten einer Sportart: Kennzahlen, Trends, Hinweise,
/// Verläufe und die Liste zum Hineinspringen.
class FitnessTrainingTab extends ConsumerStatefulWidget {
  const FitnessTrainingTab({super.key, required this.data});

  final FitnessData data;

  @override
  ConsumerState<FitnessTrainingTab> createState() => _FitnessTrainingTabState();
}

class _FitnessTrainingTabState extends ConsumerState<FitnessTrainingTab> {
  Sport? _gewaehlt;

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(fitnessZonesProvider);
    final overrides = ref.watch(fitnessOverridesProvider).value;

    Sport sportOf(Activity a) =>
        overrides?.sports[a.id] ?? a.sportDetected;
    SessionType typeOf(Activity a) =>
        overrides?.types[a.id] ?? SessionClassifier.suggest(a, zones);

    final bySport = <Sport, List<Activity>>{};
    for (final a in widget.data.activities) {
      bySport.putIfAbsent(sportOf(a), () => []).add(a);
    }

    final verfuegbar = [Sport.cycling, Sport.running, Sport.unknown]
        .where((s) => (bySport[s] ?? const []).isNotEmpty)
        .toList();

    if (verfuegbar.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Noch keine Trainingseinheiten eingelesen.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final sport = verfuegbar.contains(_gewaehlt) ? _gewaehlt! : verfuegbar.first;
    final einheiten = bySport[sport]!;
    final summary = Summarizer.summarize(sport, einheiten, zones, typeOf: typeOf)!;
    final istLauf = sport == Sport.running;
    final cadence = Analysis.cadenceCheck(sport, summary.avgCadence);

    final aufsteigend = [...einheiten]
      ..sort((a, b) => (a.date + a.timeOfDay).compareTo(b.date + b.timeOfDay));
    final absteigend = aufsteigend.reversed.toList();
    final labels = [for (final a in aufsteigend) _kurzDatum(a.date)];

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        if (verfuegbar.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final s in verfuegbar)
                  ChoiceChip(
                    selected: s == sport,
                    label: Text('${sportIcon(s)} ${sportLabel(s)}'),
                    onSelected: (_) => setState(() => _gewaehlt = s),
                  ),
              ],
            ),
          ),

        FitnessCard(
          title: 'Gesamt',
          child: FitnessValueGrid(values: [
            ('Einheiten', '${summary.count}'),
            ('Distanz', '${summary.totalKm.toStringAsFixed(1)} km'),
            ('Zeit', Analysis.formatDuration(summary.totalSec)),
            ('Ø Puls', '${summary.avgHr} bpm'),
            (
              istLauf ? 'Ø Pace' : 'Ø Tempo',
              istLauf
                  ? Analysis.formatPace(summary.avgPaceSecPerKm)
                  : '${summary.avgSpeedKmh.toStringAsFixed(1)} km/h'
            ),
            if (cadence.verdict != Verdict.noData)
              ('Ø Kadenz', '${cadence.effectiveValue} ${Analysis.cadenceUnit(sport)}'),
            ('Belastung', '${summary.loadScore} P'),
            if (summary.longest != null)
              ('Weiteste', '${summary.longest!.distanceKm.toStringAsFixed(1)} km'),
          ]),
        ),

        FitnessCard(
          title: 'Entwicklung',
          subtitle: summary.excludedFromTrends > 0
              ? 'Gerechnet ohne ${summary.excludedFromTrends} als Ausflug '
                  'eingestufte Einheit(en)'
              : 'Zweite Hälfte gegen erste Hälfte',
          child: Wrap(
            spacing: 22,
            runSpacing: 12,
            children: [
              if (istLauf)
                _Trend(
                  label: 'Pace',
                  value: summary.paceTrend,
                  einheit: ' s/km',
                  besserIstGroesser: false,
                  schwelle: 5,
                )
              else
                _Trend(
                  label: 'Tempo',
                  value: summary.speedTrend,
                  einheit: ' km/h',
                  besserIstGroesser: true,
                  schwelle: 0.3,
                ),
              _Trend(
                label: 'Puls',
                value: summary.hrTrend,
                einheit: ' bpm',
                besserIstGroesser: false,
                schwelle: 1,
              ),
              _Trend(
                label: 'Kadenz',
                value: summary.cadenceTrend,
                einheit: '',
                besserIstGroesser: true,
                schwelle: 1,
              ),
            ],
          ),
        ),

        FitnessCard(
          title: 'Was du verbessern kannst',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final t in Summarizer.insights(summary, zones))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('· $t', style: Theme.of(context).textTheme.bodyMedium),
                ),
            ],
          ),
        ),

        FitnessCard(
          title: 'Pulszonen über alle Einheiten',
          child: FitnessZoneBar(
            zoneSeconds: summary.zoneSeconds,
            labels: zones.labels,
          ),
        ),

        if (aufsteigend.length > 1) ...[
          FitnessCard(
            title: 'Puls je Einheit',
            subtitle: 'Gestrichelt: ${zones.t2} bpm',
            child: Column(children: [
              FitnessLineChart(
                smoothed: [
                  for (var i = 0; i < aufsteigend.length; i++)
                    (i, aufsteigend[i].hrAvg.toDouble()),
                ],
                goal: zones.t2.toDouble(),
                height: 140,
              ),
              FitnessAxisLabels(labels: labels),
            ]),
          ),
          FitnessCard(
            title: istLauf ? 'Pace je Einheit' : 'Ø Tempo je Einheit',
            subtitle: istLauf ? 'Niedriger ist schneller' : null,
            child: Column(children: [
              FitnessLineChart(
                smoothed: [
                  for (var i = 0; i < aufsteigend.length; i++)
                    (
                      i,
                      istLauf
                          ? aufsteigend[i].paceSecPerKm.toDouble()
                          : aufsteigend[i].speedAvgKmh
                    ),
                ],
                height: 140,
              ),
              FitnessAxisLabels(labels: labels),
            ]),
          ),
          FitnessCard(
            title: 'Distanz je Einheit',
            child: Column(children: [
              FitnessBarChart(
                values: [
                  for (final a in aufsteigend)
                    ChartValue(_kurzDatum(a.date), a.distanceKm),
                ],
              ),
            ]),
          ),
        ],

        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Text('Einheiten', style: Theme.of(context).textTheme.titleMedium),
        ),
        for (final a in absteigend)
          _EinheitTile(activity: a, sport: sport, type: typeOf(a), zones: zones),
      ],
    );
  }
}

class _Trend extends StatelessWidget {
  const _Trend({
    required this.label,
    required this.value,
    required this.einheit,
    required this.besserIstGroesser,
    required this.schwelle,
  });

  final String label;
  final double value;
  final String einheit;
  final bool besserIstGroesser;
  final double schwelle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unauffaellig = value.abs() < schwelle;
    final pfeil = unauffaellig ? '→' : (value > 0 ? '↑' : '↓');
    final gut = (besserIstGroesser == (value > 0));
    final farbe = unauffaellig
        ? scheme.onSurfaceVariant
        : (gut ? scheme.primary : scheme.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$pfeil $label',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        Text(
          '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}$einheit',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: farbe),
        ),
      ],
    );
  }
}

class _EinheitTile extends StatelessWidget {
  const _EinheitTile({
    required this.activity,
    required this.sport,
    required this.type,
    required this.zones,
  });

  final Activity activity;
  final Sport sport;
  final SessionType type;
  final HrZones zones;

  @override
  Widget build(BuildContext context) {
    final istLauf = sport == Sport.running;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () =>
            context.go('/fitness/einheit/${Uri.encodeComponent(activity.id)}'),
        title: Text(
          '${sessionTypeIcon(type)} ${_kurzDatum(activity.date)}'
          '${activity.timeOfDay.isEmpty ? '' : ' · ${activity.timeOfDay}'}',
        ),
        subtitle: Text(
          '${activity.distanceKm.toStringAsFixed(2)} km · '
          '${istLauf ? Analysis.formatPace(activity.paceSecPerKm) : '${activity.speedAvgKmh.toStringAsFixed(1)} km/h'} · '
          'Ø ${activity.hrAvg} bpm',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Analysis.formatDuration(activity.durationSec),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              '${SessionClassifier.loadScore(activity, zones)} P',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.tertiary),
            ),
          ],
        ),
      ),
    );
  }
}

String _kurzDatum(String iso) =>
    iso.length >= 10 ? '${iso.substring(8, 10)}.${iso.substring(5, 7)}' : iso;
