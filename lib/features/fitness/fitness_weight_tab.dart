import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'fitness_charts.dart';
import 'fitness_providers.dart';
import 'fitness_settings.dart';
import 'fitness_widgets.dart';
import 'weight_analysis.dart';

/// Gewichtsverlauf mit Ziel und Prognose.
class FitnessWeightTab extends ConsumerWidget {
  const FitnessWeightTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eintraege = ref.watch(mergedWeightProvider);
    final zielRoh = ref.watch(fitnessGoalWeightProvider).value ?? 0;
    final ziel = zielRoh > 0 ? zielRoh : null;
    final heute = DateTime.now();
    final scheme = Theme.of(context).colorScheme;

    if (eintraege.isEmpty) {
      return _LeerHinweis(
        onEintragen: () => _heuteEintragen(context, ref),
      );
    }

    final trend = WeightAnalysis.analyse(eintraege, ziel, heute);
    final geglaettet = WeightAnalysis.movingAverage(eintraege);
    final rohPunkte = [
      for (final p in WeightAnalysis.toPoints(eintraege)) (p.dayOffset, p.kg),
    ];
    final linie = [
      for (final p in WeightAnalysis.toPoints(geglaettet)) (p.dayOffset, p.kg),
    ];
    final auffaellig = WeightAnalysis.oddTimeDates(eintraege);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        FitnessCard(
          title: 'Trend (7-Tage-Schnitt)',
          subtitle: 'Der Tageswert schwankt durch Wasser und Salz um bis zu ein Kilo. '
              'Der geglättete Wert ist der, auf den es ankommt.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trend.trendKg == null
                    ? '—'
                    : '${trend.trendKg!.toStringAsFixed(1)} kg',
                style: Theme.of(context).textTheme.displaySmall,
              ),
              if (trend.latestRawKg != null)
                Text(
                  'zuletzt gewogen: ${trend.latestRawKg!.toStringAsFixed(1)} kg '
                  'am ${_datum(trend.latestDate)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
        ),

        FitnessCard(
          title: 'Verlauf',
          subtitle: 'Punkte = Tageswerte · Linie = 7-Tage-Schnitt'
              '${ziel != null ? ' · gestrichelt = Ziel' : ''}',
          child: Column(
            children: [
              FitnessLineChart(
                points: rohPunkte,
                smoothed: linie,
                goal: ziel,
                // Mindestspanne, sonst wird aus 300 Gramm Schwankung eine Bergkette.
                minSpan: 1.5,
                height: 190,
              ),
              FitnessAxisLabels(
                labels: [
                  _kurz(eintraege.first.date),
                  _kurz(eintraege[eintraege.length ~/ 2].date),
                  _kurz(eintraege.last.date),
                ],
              ),
            ],
          ),
        ),

        FitnessCard(
          title: 'Tempo',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                WeightAnalysis.verdictText(trend.verdict, trend.ratePerWeek),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: _farbe(trend.verdict, scheme),
                    ),
              ),
              if (trend.verdict == RateVerdict.plateau ||
                  trend.verdict == RateVerdict.zunahme)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Der Gewichtstrend ist die Messung, die Kalorienangaben deines '
                    'Trackers sind nur eine Schätzung — bei Abweichung hat der Trend recht.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
          ),
        ),

        _ZielCard(trend: trend, ziel: zielRoh),

        FitnessCard(
          title: 'Werte',
          subtitle: 'Eintragen und ändern in der Tagesansicht',
          child: Column(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Heutiges Gewicht eintragen'),
                onPressed: () => _heuteEintragen(context, ref),
              ),
              const SizedBox(height: 8),
              for (final e in eintraege.reversed.take(30))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${e.kg.toStringAsFixed(1)} kg'),
                  subtitle: Text(
                    '${_datum(e.date)}'
                    '${e.time == null ? '' : ' · ${e.time} Uhr'}'
                    '${auffaellig.contains(e.date) ? ' · andere Tageszeit als sonst' : ''}',
                    style: TextStyle(
                      color: auffaellig.contains(e.date)
                          ? scheme.tertiary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => context.go('/fitness/tag/${e.date}'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _heuteEintragen(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final heute = DateFormat('yyyy-MM-dd').format(now);
    context.go('/fitness/tag/$heute');
  }

  Color _farbe(RateVerdict v, ColorScheme scheme) => switch (v) {
        RateVerdict.gut || RateVerdict.langsam => scheme.primary,
        RateVerdict.plateau => scheme.tertiary,
        RateVerdict.zuSchnell || RateVerdict.zunahme => scheme.error,
        RateVerdict.zuWenigDaten => scheme.onSurfaceVariant,
      };
}

class _ZielCard extends ConsumerWidget {
  const _ZielCard({required this.trend, required this.ziel});

  final WeightTrend trend;
  final double ziel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final toGo = trend.toGoKg;

    return FitnessCard(
      title: 'Zielgewicht',
      subtitle: '0,25 bis 0,75 kg pro Woche sind ein Tempo, das sich halten lässt.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ziel > 0 ? '${ziel.toStringAsFixed(1)} kg' : 'Kein Ziel gesetzt',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => _zielAendern(context, ref, ziel),
                child: Text(ziel > 0 ? 'Ändern' : 'Setzen'),
              ),
            ],
          ),
          if (ziel > 0 && toGo != null) ...[
            const SizedBox(height: 6),
            if (toGo <= 0)
              Text(
                'Ziel erreicht — ${(-toGo).toStringAsFixed(1)} kg darunter.',
                style: TextStyle(color: scheme.primary),
              )
            else ...[
              Text('Noch ${toGo.toStringAsFixed(1)} kg bis zum Ziel.'),
              Text(
                trend.forecastDate != null
                    ? 'Bei diesem Tempo erreicht am '
                        '${DateFormat('dd.MM.yyyy').format(trend.forecastDate!)}.'
                    : 'Für eine Prognose fehlt ein stabiler Abwärtstrend.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: trend.forecastDate != null
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _zielAendern(BuildContext context, WidgetRef ref, double aktuell) async {
    final controller = TextEditingController(
      text: aktuell > 0 ? aktuell.toStringAsFixed(1).replaceAll('.', ',') : '',
    );
    final neu = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zielgewicht'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            suffixText: 'kg',
            helperText: 'Leer = kein Ziel',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (neu == null) return;
    final wert = double.tryParse(neu.replaceAll(',', '.')) ?? 0;
    await ref.read(fitnessGoalWeightProvider.notifier).set(wert);
  }
}

class _LeerHinweis extends StatelessWidget {
  const _LeerHinweis({required this.onEintragen});

  final VoidCallback onEintragen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Noch kein Gewicht eingetragen.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Am besten morgens nach dem Aufstehen und vor dem Frühstück wiegen — '
              'dann sind die Werte untereinander vergleichbar.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Gewicht eintragen'),
              onPressed: onEintragen,
            ),
          ],
        ),
      ),
    );
  }
}

String _datum(String? iso) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return iso ?? '';
  return DateFormat('dd.MM.yyyy').format(d);
}

String _kurz(String iso) =>
    iso.length >= 10 ? '${iso.substring(8, 10)}.${iso.substring(5, 7)}' : iso;
