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
    final ebike = ref.watch(ebikeProvider(activity));
    final istLauf = sport == Sport.running;
    final cadence = Analysis.cadenceCheck(sport, activity.cadenceAvg);
    final zoneSeconds = zones.distribute(activity.hrHistogram);
    final serie = activity.series;
    final labels = [for (final p in serie) Analysis.formatElapsed(p.elapsedSec)];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${sportIcon(sport)} ${sportLabel(sport)}'
          '${activity.indoor ? ' 🏠' : ''}${ebike ? ' ⚡' : ''}',
        ),
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
            subtitle: activity.timesEdited ? '✎ Zeiten von Hand korrigiert' : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FitnessValueGrid(values: [
                  ('Distanz', '${activity.distanceKm.toStringAsFixed(2)} km'),
                  // Bewegungszeit zuerst: das ist die Zahl, mit der überall gerechnet wird.
                  (
                    istLauf ? 'Laufzeit' : 'Fahrzeit',
                    Analysis.formatDuration(activity.activeSec)
                  ),
                  // Gesamt- und Standzeit immer zeigen, auch ohne Pause: Nur so sieht man
                  // auf einen Blick, ob die Aufteilung stimmt.
                  ('Gesamtzeit', Analysis.formatDuration(activity.durationSec)),
                  (
                    'Standzeit',
                    '${Analysis.formatDuration(activity.pausedSec)}'
                        ' · ${(activity.stoppedShare * 100).round()} %'
                  ),
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
                  // Watt stehen bewusst vorn und nicht unter „Weitere Messwerte": Wo es sie
                  // gibt, sind sie die belastbarste Zahl der ganzen Einheit.
                  if (activity.powerAvg > 0)
                    (
                      activity.powerDerived ? 'Ø Leistung (gerechnet)' : 'Ø Leistung',
                      '${activity.powerAvg} W'
                    ),
                  if (activity.powerMax > 0) ('Max Leistung', '${activity.powerMax} W'),
                  if (cadence.verdict != Verdict.noData)
                    (
                      'Ø Kadenz',
                      '${cadence.effectiveValue} ${Analysis.cadenceUnit(sport)}'
                    ),
                  if (activity.elevGain > 0 || activity.elevLoss > 0)
                    ('Höhenmeter', '${activity.elevGain} ↑ / ${activity.elevLoss} ↓'),
                  ('Belastung', '${SessionClassifier.loadScore(activity, zones)} P'),
                ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Zeiten korrigieren'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _ZeitenDialog(
                        activity: activity,
                        ausDatei:
                            ref.read(fitnessDataProvider.notifier).rohe(activity.id),
                        istLauf: istLauf,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (activity.hasTrack)
            FitnessCard(
              title: 'Strecke',
              subtitle: 'Farbe nach Tempo · grün Start, rot Ziel',
              child: FitnessRouteMap(points: serie),
            ),

          if (activity.laps.length > 1)
            FitnessCard(
              title: 'Runden',
              subtitle: !activity.laps.any((l) => l.avgPower > 0)
                  ? 'Abschnitte der Einheit'
                  : (activity.powerDerived
                      ? 'Watt je Abschnitt — aus der Trittfrequenz gerechnet, nicht '
                          'gemessen'
                      : 'Watt je Abschnitt — daran hängt, ob die Einheit wirklich '
                          'strukturiert war'),
              child: _RundenTabelle(laps: activity.laps),
            ),

          _EinstufungCard(
            activity: activity,
            sport: sport,
            type: type,
            zones: zones,
            ebike: ebike,
          ),

          FitnessCard(
            title: 'Was dir das sagt',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final tipp
                    in activityTips(activity, sport, type, zones, ebike: ebike))
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
    required this.ebike,
  });

  final Activity activity;
  final Sport sport;
  final SessionType type;
  final HrZones zones;
  final bool ebike;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final erkannt = activity.sportDetected;
    final vorschlag = SessionClassifier.suggest(activity, zones);
    final ctrl = ref.read(fitnessOverridesProvider.notifier);

    // Eingeklappt, weil die Einstufung meist stimmt und nur im Ausnahmefall angefasst
    // wird — aufgeklappt stünde sie dauerhaft zwischen den Kennzahlen und der
    // Auswertung im Weg.
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Text(
          'Einstufung',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          '${sportIcon(sport)} ${sportLabel(sport)} · '
          '${sessionTypeIcon(type)} ${sessionTypeLabel(type)}'
          '${ebike ? ' · ⚡ E-Motor' : ''}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        children: [Column(
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
          // Nur beim Rad: einen Motor am Laufschuh gibt es nicht, und ein Kästchen, das
          // nie zutrifft, macht die Karte nur voller.
          if (sport != Sport.running) ...[
            const SizedBox(height: 6),
            CheckboxListTile(
              value: ebike,
              onChanged: (an) => ctrl.setEbike(activity.id, an ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: const Text('⚡ Mit E-Motor-Unterstützung'),
              subtitle: Text(
                'Zeit, Distanz und Belastung zählen normal mit. Nur aus den '
                'Leistungstrends bleibt die Fahrt heraus — sonst sähe der Motor wie '
                'deine Form aus.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            activity.sportDeclared != null
                // Bei FIT- und TCX-Dateien steht die Sportart in der Datei. Von einer
                // „Erkennung mit 100 % Sicherheit" zu sprechen wäre eine Zahl, die nur
                // so tut, als sei etwas gemessen worden.
                ? 'Sportart und Ort stehen in der Datei selbst.'
                : 'Sportart erkannt an ${activity.metersPerCycle.toStringAsFixed(1)} m pro '
                    'Zyklus (Sicherheit ${(activity.sportConfidence * 100).round()} %).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      )],
      ),
    );
  }
}

/// Gesamt- und Standzeit von Hand eintragen, die Fahr- bzw. Laufzeit ergibt sich daraus.
///
/// Drei getrennte Felder für Stunden, Minuten und Sekunden statt einer Eingabe wie
/// „24:27": Die ließe offen, ob Minuten und Sekunden oder Stunden und Minuten gemeint
/// sind — und genau bei der Standzeit ist beides plausibel.
class _ZeitenDialog extends ConsumerStatefulWidget {
  const _ZeitenDialog({
    required this.activity,
    required this.ausDatei,
    required this.istLauf,
  });

  final Activity activity;
  final Activity? ausDatei;
  final bool istLauf;

  @override
  ConsumerState<_ZeitenDialog> createState() => _ZeitenDialogState();
}

class _ZeitenDialogState extends ConsumerState<_ZeitenDialog> {
  late final List<TextEditingController> _gesamt;
  late final List<TextEditingController> _stand;

  @override
  void initState() {
    super.initState();
    _gesamt = _felder(widget.activity.durationSec);
    _stand = _felder(widget.activity.pausedSec);
  }

  @override
  void dispose() {
    for (final c in [..._gesamt, ..._stand]) {
      c.dispose();
    }
    super.dispose();
  }

  static List<TextEditingController> _felder(int sec) => [
    TextEditingController(text: '${sec ~/ 3600}'),
    TextEditingController(text: '${(sec % 3600) ~/ 60}'),
    TextEditingController(text: '${sec % 60}'),
  ];

  /// `null`, solange ein Feld keine gültige Zahl enthält.
  static int? _sekunden(List<TextEditingController> f) {
    final werte = [
      for (final c in f)
        int.tryParse(c.text.trim().isEmpty ? '0' : c.text.trim()),
    ];
    if (werte.any((w) => w == null || w < 0)) return null;
    return werte[0]! * 3600 + werte[1]! * 60 + werte[2]!;
  }

  @override
  Widget build(BuildContext context) {
    final gesamt = _sekunden(_gesamt);
    final stand = _sekunden(_stand);
    final fehler = gesamt == null || stand == null
        ? 'Bitte nur ganze Zahlen eintragen.'
        : (gesamt == 0
              ? 'Die Gesamtzeit darf nicht null sein.'
              : (stand > gesamt
                    ? 'Die Standzeit ist länger als die Gesamtzeit.'
                    : null));
    final datei = widget.ausDatei;
    final grau = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return AlertDialog(
      title: const Text('Zeiten korrigieren'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gesamtzeit', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            _DauerFelder(felder: _gesamt, onChanged: () => setState(() {})),
            const SizedBox(height: 14),
            Text('Standzeit', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 6),
            _DauerFelder(felder: _stand, onChanged: () => setState(() {})),
            const SizedBox(height: 14),
            if (fehler != null)
              Text(
                fehler,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else
              Text(
                '${widget.istLauf ? 'Laufzeit' : 'Fahrzeit'}: '
                '${Analysis.formatDuration(gesamt! - stand!)}'
                ' · ${(stand / gesamt * 100).round()} % Stand',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            if (datei != null) ...[
              const SizedBox(height: 10),
              Text(
                'Aus der Datei: gesamt ${Analysis.formatDuration(datei.durationSec)}, '
                'Stand ${Analysis.formatDuration(datei.pausedSec)}',
                style: grau,
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (widget.activity.timesEdited)
          TextButton(
            onPressed: () {
              ref
                  .read(fitnessOverridesProvider.notifier)
                  .setTimes(widget.activity.id, null);
              Navigator.pop(context);
            },
            child: const Text('Zurück auf Datei'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: fehler != null
              ? null
              : () {
                  ref
                      .read(fitnessOverridesProvider.notifier)
                      .setTimes(
                        widget.activity.id,
                        TimeEdit(totalSec: gesamt!, stoppedSec: stand!),
                      );
                  Navigator.pop(context);
                },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _DauerFelder extends StatelessWidget {
  const _DauerFelder({required this.felder, required this.onChanged});

  final List<TextEditingController> felder;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    const einheiten = ['Std', 'Min', 'Sek'];
    return Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: felder[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                isDense: true,
                suffixText: einheiten[i],
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Runden als schmale Tabelle.
///
/// Bewusst keine Karte je Runde: Bei neun Minutenstufen zählt der Vergleich
/// untereinander, und der geht nur, wenn die Zahlen in einer Spalte stehen.
class _RundenTabelle extends StatelessWidget {
  const _RundenTabelle({required this.laps});

  final List<ActivityLap> laps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final klein = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        );
    final wert = Theme.of(context).textTheme.bodySmall;
    final mitWatt = laps.any((l) => l.avgPower > 0);
    // Die stärkste Runde bekommt den Balken zum Vergleich — ohne Bezugsgröße sagt eine
    // Wattzahl allein wenig.
    final maxWatt = laps.fold<int>(1, (m, l) => l.avgPower > m ? l.avgPower : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          SizedBox(width: 24, child: Text('#', style: klein)),
          SizedBox(width: 52, child: Text('Dauer', style: klein)),
          SizedBox(width: 52, child: Text('km', style: klein)),
          if (mitWatt) SizedBox(width: 48, child: Text('Ø Watt', style: klein)),
          Expanded(child: Text('Ø Puls', style: klein, textAlign: TextAlign.right)),
        ]),
        const Divider(height: 12),
        for (final l in laps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 24, child: Text('${l.number}', style: wert)),
                SizedBox(
                  width: 52,
                  child: Text(Analysis.formatDuration(l.durationSec), style: wert),
                ),
                SizedBox(
                  width: 52,
                  child: Text(l.distanceKm.toStringAsFixed(2), style: wert),
                ),
                if (mitWatt)
                  SizedBox(
                    width: 48,
                    child: Text(l.avgPower > 0 ? '${l.avgPower}' : '—', style: wert),
                  ),
                Expanded(
                  child: mitWatt
                      ? _WattBalken(anteil: l.avgPower / maxWatt, farbe: scheme.tertiary)
                      : const SizedBox.shrink(),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    l.avgHr > 0 ? '${l.avgHr}' : '—',
                    style: wert,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _WattBalken extends StatelessWidget {
  const _WattBalken({required this.anteil, required this.farbe});

  final double anteil;
  final Color farbe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 6,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: farbe.withValues(alpha: 0.18)),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: anteil.clamp(0.0, 1.0),
                  // heightFactor: sonst bestimmt das Kind die Höhe, und eine ColoredBox
                  // ohne Kind nimmt bei loser Vorgabe null. Derselbe Fallstrick wie beim
                  // Wochenbalken.
                  heightFactor: 1,
                  child: ColoredBox(color: farbe),
                ),
              ),
            ],
          ),
        ),
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
          FitnessLineChart(smoothed: verlauf, height: 110),
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
