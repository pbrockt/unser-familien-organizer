import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_analysis.dart';
import 'fitness_charts.dart';
import 'fitness_models.dart';
import 'fitness_overrides.dart';
import 'fitness_providers.dart';
import 'fitness_route_map.dart';
import 'fitness_settings.dart';
import 'fitness_widgets.dart';

/// Vollständige Auswertung einer einzelnen Einheit.
class FitnessActivityScreen extends ConsumerWidget {
  const FitnessActivityScreen({super.key, required this.activityId});

  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(fitnessDataProvider).value;
    final activity = data?.activities.where((a) => a.id == activityId).firstOrNull;

    if (activity == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Einheit')),
        body: const Center(child: Text('Diese Einheit ist nicht mehr vorhanden.')),
      );
    }

    final zones = ref.watch(fitnessZonesProvider);
    final sport = ref.watch(effectiveSportProvider(activity));
    final type = ref.watch(effectiveTypeProvider(activity));
    final istLauf = sport == Sport.running;
    final cadence = Analysis.cadenceCheck(sport, activity.cadenceAvg);
    final zoneSeconds = zones.distribute(activity.hrHistogram);
    final serie = activity.series;
    final labels = [for (final p in serie) Analysis.formatElapsed(p.elapsedSec)];

    return Scaffold(
      appBar: AppBar(
        title: Text('${sportIcon(sport)} ${sportLabel(sport)}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${_datum(activity.date)}'
              '${activity.timeOfDay.isEmpty ? '' : ' · ${activity.timeOfDay}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          FitnessCard(
            title: 'Kennzahlen',
            child: FitnessValueGrid(values: [
              ('Distanz', '${activity.distanceKm.toStringAsFixed(2)} km'),
              ('Dauer', Analysis.formatDuration(activity.durationSec)),
              (
                istLauf ? 'Pace' : 'Ø Tempo',
                istLauf
                    ? Analysis.formatPace(activity.paceSecPerKm)
                    : '${activity.speedAvgKmh.toStringAsFixed(1)} km/h'
              ),
              if (!istLauf && activity.speedMovingAvgKmh > 0)
                (
                  'Ø in Bewegung',
                  '${activity.speedMovingAvgKmh.toStringAsFixed(1)} km/h'
                ),
              ('Max Tempo', '${activity.speedMaxKmh.toStringAsFixed(1)} km/h'),
              ('Ø Puls', '${activity.hrAvg} bpm'),
              ('Max Puls', '${activity.hrMax} bpm'),
              if (cadence.verdict != Verdict.noData)
                (
                  'Ø Kadenz',
                  '${cadence.effectiveValue} ${Analysis.cadenceUnit(sport)}'
                ),
              if (activity.elevGain > 0 || activity.elevLoss > 0)
                ('Höhenmeter', '${activity.elevGain} ↑ / ${activity.elevLoss} ↓'),
              ('Belastung', '${SessionClassifier.loadScore(activity, zones)} P'),
              ('Standzeit', '${(activity.stoppedShare * 100).round()} %'),
            ]),
          ),

          if (activity.hasTrack)
            FitnessCard(
              title: 'Strecke',
              subtitle: 'Farbe nach Tempo · grün Start, rot Ziel',
              child: FitnessRouteMap(points: serie),
            ),

          _EinstufungCard(activity: activity, sport: sport, type: type, zones: zones),

          FitnessCard(
            title: 'Was dir das sagt',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tipp in activityTips(activity, sport, type, zones))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('· $tipp',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
              ],
            ),
          ),

          FitnessCard(
            title: 'Pulszonen',
            subtitle: cadence.perLeg
                ? 'Kadenz wird pro Bein gezählt und zur Bewertung verdoppelt'
                : null,
            child: FitnessZoneBar(zoneSeconds: zoneSeconds, labels: zones.labels),
          ),

          if (serie.length > 1) ...[
            FitnessCard(
              title: 'Puls im Verlauf',
              subtitle: 'Gestrichelt: ${zones.t2} bpm',
              child: Column(children: [
                FitnessLineChart(
                  points: const [],
                  smoothed: [
                    for (final p in serie)
                      if (p.hr > 0) (p.elapsedSec, p.hr.toDouble()),
                  ],
                  goal: zones.t2.toDouble(),
                  height: 150,
                ),
                FitnessAxisLabels(labels: labels),
              ]),
            ),
            FitnessCard(
              title: 'Geschwindigkeit',
              child: Column(children: [
                FitnessLineChart(
                  points: const [],
                  smoothed: [
                    for (final p in serie) (p.elapsedSec, p.speedKmh),
                  ],
                  height: 150,
                ),
                FitnessAxisLabels(labels: labels),
              ]),
            ),
            if (activity.cadenceAvg > 0)
              FitnessCard(
                title: 'Kadenz',
                subtitle: Analysis.cadenceTargetLabel(sport),
                child: Column(children: [
                  FitnessLineChart(
                    points: const [],
                    smoothed: [
                      for (final p in serie)
                        if (p.cadence > 0)
                          (
                            p.elapsedSec,
                            (cadence.perLeg ? p.cadence * 2 : p.cadence).toDouble()
                          ),
                    ],
                    goal: Analysis.cadenceTarget(sport),
                    height: 150,
                  ),
                  FitnessAxisLabels(labels: labels),
                ]),
              ),
            FitnessCard(
              title: 'Höhenprofil',
              child: Column(children: [
                FitnessLineChart(
                  points: const [],
                  smoothed: [for (final p in serie) (p.elapsedSec, p.altitude)],
                  height: 130,
                ),
                FitnessAxisLabels(labels: labels),
              ]),
            ),
          ],

          if (activity.channels.isNotEmpty)
            _WeitereKanaele(activity: activity, labels: labels),
        ],
      ),
    );
  }
}

class _EinstufungCard extends ConsumerWidget {
  const _EinstufungCard({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final erkannt = activity.sportDetected;
    final vorschlag = SessionClassifier.suggest(activity, zones);
    final ctrl = ref.read(fitnessOverridesProvider.notifier);

    return FitnessCard(
      title: 'Einstufung',
      subtitle: 'Erkannt an ${activity.metersPerCycle.toStringAsFixed(1)} m pro Zyklus '
          '(Sicherheit ${(activity.sportConfidence * 100).round()} %). '
          'Stimmt etwas nicht, hier ändern.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sportart', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final option in [Sport.cycling, Sport.running])
                ChoiceChip(
                  selected: sport == option,
                  label: Text('${sportIcon(option)} ${sportLabel(option)}'),
                  // Erneutes Wählen des Erkannten nimmt die Festlegung zurück.
                  onSelected: (_) =>
                      ctrl.setSport(activity.id, option == erkannt ? null : option),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Art der Einheit', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            'Ausflüge zählen bei Distanz und Belastung mit, bleiben aber aus den Trends '
            'heraus — sonst sieht eine gemütliche Runde wie ein Rückschritt aus.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final option in SessionType.values)
                ChoiceChip(
                  selected: type == option,
                  label: Text('${sessionTypeIcon(option)} ${sessionTypeLabel(option)}'),
                  onSelected: (_) =>
                      ctrl.setType(activity.id, option == vorschlag ? null : option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeitereKanaele extends StatelessWidget {
  const _WeitereKanaele({required this.activity, required this.labels});

  final Activity activity;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final namen = activity.channels.keys.toList()..sort();

    return FitnessCard(
      title: 'Weitere Messwerte',
      subtitle: 'Alles, was sonst noch in der Datei steht',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final name in namen) ...[
            _KanalBlock(
              stat: activity.channels[name]!,
              verlauf: [
                for (final p in activity.series)
                  if (p.extra[name] != null) (p.elapsedSec, p.extra[name]!),
              ],
              labels: labels,
            ),
            if (name != namen.last) const Divider(height: 24),
          ],
        ],
      ),
    );
  }
}

class _KanalBlock extends StatelessWidget {
  const _KanalBlock({
    required this.stat,
    required this.verlauf,
    required this.labels,
  });

  final ChannelStat stat;
  final List<(int, double)> verlauf;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    // Konstante Spalten (min == max) als Verlauf zu zeichnen wäre eine gerade Linie
    // ohne Aussage — dann genügt der Wert.
    final konstant = (stat.max - stat.min).abs() < 0.0001;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(stat.name, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        FitnessValueGrid(values: [
          if (konstant)
            ('Wert', _fmt(stat.avg))
          else ...[
            ('Ø', _fmt(stat.avg)),
            ('min', _fmt(stat.min)),
            ('max', _fmt(stat.max)),
          ],
          ('Messwerte', '${stat.count}'),
        ]),
        if (!konstant && verlauf.length > 1) ...[
          const SizedBox(height: 10),
          FitnessLineChart(points: const [], smoothed: verlauf, height: 110),
          FitnessAxisLabels(labels: labels),
        ],
      ],
    );
  }

  String _fmt(double v) {
    if (v.abs() >= 1000) return v.round().toString();
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }
}

String _datum(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';
}
