import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'fitness_analysis.dart';
import 'fitness_models.dart';
import 'fitness_overrides.dart';
import 'fitness_providers.dart';
import 'fitness_screen.dart';
import 'fitness_settings.dart';
import 'fitness_widgets.dart';
import 'weight_analysis.dart';

/// Details eines einzelnen Tages: Gewicht, Gesundheitsdaten und die Einheiten des Tages.
class FitnessDayScreen extends ConsumerWidget {
  const FitnessDayScreen({super.key, required this.date});

  final String date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(fitnessDataProvider).value;
    final stepGoal = ref.watch(fitnessStepGoalProvider).value ?? 8000;
    final gewichte = ref.watch(mergedWeightProvider);

    final day = data == null
        ? null
        : buildDays(data).where((d) => d.date == date).firstOrNull;
    final gewichtHeute =
        gewichte.where((e) => e.date == date).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(_langDatum(date))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          _GewichtCard(date: date, eintrag: gewichtHeute, alle: gewichte),
          if (day?.health != null) _HealthCard(day!.health!, stepGoal),
          if (day == null || day.activities.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'An diesem Tag ist keine Trainingseinheit aufgezeichnet.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final a in day.activities) _ActivityTile(activity: a),
        ],
      ),
    );
  }
}

class _GewichtCard extends ConsumerWidget {
  const _GewichtCard({
    required this.date,
    required this.eintrag,
    required this.alle,
  });

  final String date;
  final WeightEntry? eintrag;
  final List<WeightEntry> alle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final auffaellig = WeightAnalysis.oddTimeDates(alle).contains(date);

    return FitnessCard(
      title: 'Gewicht',
      subtitle: 'Am besten morgens nach dem Aufstehen — dann sind die Werte '
          'untereinander vergleichbar.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (eintrag == null)
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Gewicht eintragen'),
              onPressed: () => _eingabe(context, ref, date, null),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${eintrag!.kg.toStringAsFixed(1)} kg',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        eintrag!.time == null
                            ? 'ohne Uhrzeit'
                            : 'gewogen um ${eintrag!.time} Uhr',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Ändern',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _eingabe(context, ref, date, eintrag),
                ),
                IconButton(
                  tooltip: 'Löschen',
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: () =>
                      ref.read(weightEntriesProvider.notifier).remove(date),
                ),
              ],
            ),
            if (auffaellig)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Zu einer anderen Tageszeit gewogen als sonst. Über den Tag schwankt '
                  'das Gewicht um bis zu zwei Kilo — dieser Wert ist mit den übrigen '
                  'nur eingeschränkt vergleichbar.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.tertiary,
                      ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _eingabe(
    BuildContext context,
    WidgetRef ref,
    String date,
    WeightEntry? vorhanden,
  ) async {
    final ergebnis = await showDialog<(double, String?)>(
      context: context,
      builder: (_) => _GewichtDialog(vorhanden: vorhanden),
    );
    if (ergebnis == null) return;
    await ref
        .read(weightEntriesProvider.notifier)
        .put(date, ergebnis.$1, time: ergebnis.$2);
  }
}

class _GewichtDialog extends StatefulWidget {
  const _GewichtDialog({this.vorhanden});

  final WeightEntry? vorhanden;

  @override
  State<_GewichtDialog> createState() => _GewichtDialogState();
}

class _GewichtDialogState extends State<_GewichtDialog> {
  late final TextEditingController _kg = TextEditingController(
    text: widget.vorhanden == null
        ? ''
        : widget.vorhanden!.kg.toStringAsFixed(1).replaceAll('.', ','),
  );
  late TimeOfDay? _zeit = _parse(widget.vorhanden?.time) ?? TimeOfDay.now();

  static TimeOfDay? _parse(String? hhmm) {
    if (hhmm == null || hhmm.length < 4) return null;
    final teile = hhmm.split(':');
    if (teile.length != 2) return null;
    final h = int.tryParse(teile[0]);
    final m = int.tryParse(teile[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  void dispose() {
    _kg.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Komma zulassen — auf der deutschen Zifferntastatur liegt kein Punkt.
    final wert = double.tryParse(_kg.text.replaceAll(',', '.'));
    final gueltig = wert != null && wert >= 20 && wert <= 400;

    return AlertDialog(
      title: const Text('Gewicht eintragen'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _kg,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'kg'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: Text(_zeit == null
                ? 'Uhrzeit angeben'
                : '${_zeit!.hour.toString().padLeft(2, '0')}:'
                    '${_zeit!.minute.toString().padLeft(2, '0')} Uhr'),
            subtitle: const Text('Macht Werte vergleichbar'),
            trailing: _zeit == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Uhrzeit entfernen',
                    onPressed: () => setState(() => _zeit = null),
                  ),
            onTap: () async {
              final gewaehlt = await showTimePicker(
                context: context,
                initialTime: _zeit ?? TimeOfDay.now(),
              );
              if (gewaehlt != null) setState(() => _zeit = gewaehlt);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: gueltig
              ? () => Navigator.of(context).pop((
                  wert,
                  _zeit == null
                      ? null
                      : '${_zeit!.hour.toString().padLeft(2, '0')}:'
                          '${_zeit!.minute.toString().padLeft(2, '0')}',
                ))
              : null,
          child: const Text('Speichern'),
        ),
      ],
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

    return FitnessCard(
      title: 'Tagesdaten',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (steps != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text('$steps Schritte',
                      style: Theme.of(context).textTheme.headlineSmall),
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
          FitnessValueGrid(values: [
            if (health.restingHr != null)
              ('Ruhepuls', '${health.restingHr} bpm'),
            if (health.hrAvg != null) ('Ø Puls', '${health.hrAvg} bpm'),
            if (health.hrMin != null && health.hrMax != null)
              ('Puls min/max', '${health.hrMin}/${health.hrMax}'),
            if (health.exerciseMinutes != null)
              ('Bewegung', '${health.exerciseMinutes} min'),
            if (health.walkingRunningKm != null)
              ('zu Fuß', '${health.walkingRunningKm!.toStringAsFixed(2)} km'),
            if (health.totalCalories != null)
              ('Kalorien', '${health.totalCalories}'),
            if (health.activeCalories != null)
              ('davon aktiv', '${health.activeCalories}'),
            if (health.basalCalories != null)
              ('Grundumsatz', '${health.basalCalories}'),
            if (health.spo2Avg != null) ('SpO₂', '${health.spo2Avg} %'),
          ]),
          if (health.sleepHours != null) ...[
            const SizedBox(height: 16),
            _SchlafBlock(health: health),
          ],
          if ((health.workoutCount ?? 0) > 0) ...[
            const SizedBox(height: 16),
            _WorkoutBlock(health: health),
          ],
        ],
      ),
    );
  }
}

/// Schlafphasen des Tages — acht Stunden im Bett sind nicht acht gute Stunden.
class _SchlafBlock extends StatelessWidget {
  const _SchlafBlock({required this.health});

  final HealthDay health;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gesamt = health.sleepHours!;
    final tief = health.sleepDeepHours;
    final rem = health.sleepRemHours;
    final kern = health.sleepCoreHours;
    final wach = health.sleepAwakeHours;

    String std(double? h) => h == null ? '—' : '${h.toStringAsFixed(1)} h';
    String anteil(double? h) =>
        (h == null || gesamt <= 0) ? '' : ' (${(h / gesamt * 100).round()} %)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Schlaf', style: Theme.of(context).textTheme.labelLarge),
            ),
            if (health.bedtime != null && health.wakeTime != null)
              Text(
                '${health.bedtime} – ${health.wakeTime}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (tief != null || rem != null) ...[
          // Balken in der Reihenfolge der Erholungswirkung: tief, REM, Kern, wach.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final (wert, farbe) in [
                    (tief, scheme.primary),
                    (rem, scheme.primary.withValues(alpha: 0.6)),
                    (kern, scheme.primary.withValues(alpha: 0.3)),
                    (wach, scheme.error.withValues(alpha: 0.55)),
                  ])
                    if (wert != null && wert > 0)
                      Expanded(
                        flex: (wert * 100).round(),
                        child: ColoredBox(color: farbe),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        FitnessValueGrid(values: [
          ('gesamt', std(gesamt)),
          if (tief != null) ('tief', '${std(tief)}${anteil(tief)}'),
          if (rem != null) ('REM', '${std(rem)}${anteil(rem)}'),
          if (kern != null) ('Kern', std(kern)),
          if (wach != null) ('wach', std(wach)),
        ]),
      ],
    );
  }
}

/// Trainingseinheiten, die der Tracker gezählt hat — auch solche ohne eigene Tour-Datei.
class _WorkoutBlock extends StatelessWidget {
  const _WorkoutBlock({required this.health});

  final HealthDay health;

  @override
  Widget build(BuildContext context) {
    final arten = health.workouts.isEmpty
        ? ''
        : ' · ${health.workouts.map(_uebersetzt).join(', ')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Vom Tracker gezählt$arten',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        FitnessValueGrid(values: [
          ('Einheiten', '${health.workoutCount}'),
          if (health.workoutMinutes != null)
            ('Dauer', '${health.workoutMinutes} min'),
          if (health.workoutDistanceKm != null)
            ('Distanz', '${health.workoutDistanceKm!.toStringAsFixed(2)} km'),
          if (health.workoutAvgHr != null)
            ('Ø Puls', '${health.workoutAvgHr} bpm'),
        ]),
      ],
    );
  }

  String _uebersetzt(String art) => switch (art.toLowerCase()) {
        'walking' => 'Gehen',
        'running' => 'Laufen',
        'cycling' || 'biking' => 'Radfahren',
        'other' => 'Sonstiges',
        _ => art,
      };
}

class _ActivityTile extends ConsumerWidget {
  const _ActivityTile({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sport = ref.watch(effectiveSportProvider(activity));
    final type = ref.watch(effectiveTypeProvider(activity));
    final zones = ref.watch(fitnessZonesProvider);
    final istLauf = sport == Sport.running;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go('/fitness/einheit/${Uri.encodeComponent(activity.id)}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${sportIcon(sport)} ${sportLabel(sport)} · '
                      '${sessionTypeIcon(type)} ${sessionTypeLabel(type)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    activity.timeOfDay,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 10),
              FitnessValueGrid(values: [
                ('Distanz', '${activity.distanceKm.toStringAsFixed(2)} km'),
                ('Dauer', Analysis.formatDuration(activity.durationSec)),
                (
                  istLauf ? 'Pace' : 'Ø Tempo',
                  istLauf
                      ? Analysis.formatPace(activity.paceSecPerKm)
                      : '${activity.speedAvgKmh.toStringAsFixed(1)} km/h'
                ),
                ('Ø Puls', '${activity.hrAvg} bpm'),
                ('Belastung', '${SessionClassifier.loadScore(activity, zones)} P'),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

String _langDatum(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  const wochentage = [
    'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag',
  ];
  final wt = wochentage[(d.weekday - 1).clamp(0, 6)];
  return '$wt, ${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';
}
