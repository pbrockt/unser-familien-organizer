import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../fitness/fitness_models.dart';
import '../fitness/fitness_providers.dart';
import '../fitness/fitness_settings.dart';
import '../fitness/fitness_widgets.dart';
import 'food_search_sheet.dart';
import 'nutrition_analysis.dart';
import 'nutrition_models.dart';
import 'nutrition_providers.dart';

/// Ernährungstagebuch eines Tages: Summe gegen Ziel, Makros, Mahlzeiten.
class NutritionTab extends ConsumerStatefulWidget {
  const NutritionTab({super.key});

  @override
  ConsumerState<NutritionTab> createState() => _NutritionTabState();
}

class _NutritionTabState extends ConsumerState<NutritionTab> {
  DateTime _tag = DateTime.now();

  String get _datum => DateFormat('yyyy-MM-dd').format(_tag);

  void _schiebe(int tage) =>
      setState(() => _tag = DateTime(_tag.year, _tag.month, _tag.day + tage));

  Future<void> _abgleich() async {
    final fehler = await ref.read(nutritionProvider.notifier).sync();
    if (fehler != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fehler)));
    }
  }

  Future<void> _alsVorlage(Meal m, List<MealEntry> eintraege) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _VorlagenName(vorschlag: 'Mein ${mealLabel(m)}'),
    );
    if (name == null || name.trim().isEmpty) return;
    await ref.read(nutritionProvider.notifier).saveTemplate(name.trim(), eintraege);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('„${name.trim()}" gespeichert — beim nächsten Eintragen ganz oben.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final daten = ref.watch(nutritionProvider).value;
    final ziel = ref.watch(fitnessKcalGoalProvider).value ?? 2000;
    final tag = daten?.day(_datum) ?? NutritionDay(date: _datum);
    final heute = DateTime.now();
    final istHeute = DateUtils.isSameDay(_tag, heute);
    final scheme = Theme.of(context).colorScheme;
    final grau = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        );
    final gesundheit = {
      for (final h in ref.watch(fitnessDataProvider).value?.healthDays ??
          const <HealthDay>[])
        h.date: h,
    };
    final verbraucht = gesundheit[_datum]?.totalCalories;
    final woche = daten == null
        ? null
        : weekSummary(data: daten, health: gesundheit, heute: heute);

    return RefreshIndicator(
      onRefresh: _abgleich,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Tag davor',
                onPressed: () => _schiebe(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  istHeute
                      ? 'Heute, ${DateFormat('d. MMMM', 'de_DE').format(_tag)}'
                      : DateFormat('EEEE, d. MMMM', 'de_DE').format(_tag),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Tag danach',
                onPressed: istHeute ? null : () => _schiebe(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          FitnessCard(
            title: 'Gegessen',
            subtitle: (daten?.pendingDays.isNotEmpty ?? false)
                ? 'Noch nicht in der Nextcloud — wird beim nächsten Abgleich nachgeholt'
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${tag.kcal.round()}',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text('/ $ziel kcal', style: grau),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        tag.kcal <= ziel
                            ? 'noch ${(ziel - tag.kcal).round()} kcal'
                            : '${(tag.kcal - ziel).round()} kcal drüber',
                        style: grau,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: ziel <= 0 ? 0 : (tag.kcal / ziel).clamp(0.0, 1.0),
                    color: tag.kcal > ziel ? scheme.error : scheme.primary,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 10),
                FitnessValueGrid(values: [
                  ('Eiweiß', '${tag.protein.round()} g'),
                  ('Kohlenhydrate', '${tag.carbs.round()} g'),
                  ('Fett', '${tag.fat.round()} g'),
                  // Verbrauch aus Health Connect. Heute ist er erst der Stand bis jetzt —
                  // die Bilanz am Abend sieht anders aus als am Mittag.
                  if (verbraucht != null && verbraucht > 0) ...[
                    (istHeute ? 'Verbraucht bisher' : 'Verbraucht', '$verbraucht kcal'),
                    if (tag.entries.isNotEmpty)
                      ('Bilanz', _bilanz(tag.kcal - verbraucht)),
                  ],
                ]),
              ],
            ),
          ),
          _WasserKarte(
            ml: tag.waterMl,
            zielMl: ref.watch(fitnessWaterGoalProvider).value ?? 2000,
            onSet: (ml) => ref.read(nutritionProvider.notifier).setWater(_datum, ml),
          ),
          for (final m in Meal.values)
            _MahlzeitKarte(
              meal: m,
              eintraege: tag.ofMeal(m),
              onAdd: () => showFoodSearch(context, date: _datum, meal: m),
              onChange: (e, g) =>
                  ref.read(nutritionProvider.notifier).changeGrams(_datum, e, g),
              onRemove: (e) => ref.read(nutritionProvider.notifier).remove(_datum, e),
              onSaveTemplate: () => _alsVorlage(m, tag.ofMeal(m)),
            ),
          if (woche != null && woche.erfasst > 0)
            FitnessCard(
              title: 'Letzte 7 Tage',
              subtitle: 'Ohne heute · Durchschnitt über ${woche.erfasst} erfasste '
                  '${woche.erfasst == 1 ? 'Tag' : 'Tage'} — Tage ohne Einträge zählen nicht '
                  'als 0',
              child: FitnessValueGrid(values: [
                ('Ø gegessen', '${woche.avgEaten!.round()} kcal'),
                if (woche.avgBurned != null)
                  ('Ø verbraucht', '${woche.avgBurned!.round()} kcal'),
                if (woche.avgBalance != null)
                  ('Ø Bilanz', _bilanz(woche.avgBalance!)),
                ('Ø Eiweiß', '${woche.avgProtein!.round()} g'),
                ('Ø Kohlenhydrate', '${woche.avgCarbs!.round()} g'),
                ('Ø Fett', '${woche.avgFat!.round()} g'),
              ]),
            ),
          const SizedBox(height: 4),
          Text(
            'Nährwerte von Open Food Facts (openfoodfacts.org, ODbL). Das Tagebuch liegt in '
            'deinem Datenordner unter „Ernährung".',
            style: grau,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Gläser à 250 ml zum Antippen.
class _WasserKarte extends StatelessWidget {
  const _WasserKarte({required this.ml, required this.zielMl, required this.onSet});

  final int ml;
  final int zielMl;
  final void Function(int) onSet;

  static const glasMl = 250;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ziel = (zielMl / glasMl).round().clamp(1, 24);
    final voll = (ml / glasMl).floor();
    // Über das Ziel hinaus Getrunkenes bleibt sichtbar: ein Glas mehr als volle.
    final anzahl = voll >= ziel ? voll + 1 : ziel;
    // 0 → „0", 750 → „0,75", 1500 → „1,5", 2000 → „2". Nullen nur hinter dem Komma
    // abschneiden — sonst würden aus 10 Litern 1.
    String liter(int v) {
      if (v % 1000 == 0) return '${v ~/ 1000}';
      final s = (v / 1000).toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
      return s.replaceAll('.', ',');
    }

    return FitnessCard(
      title: '💧 Wasser',
      subtitle: '${liter(ml)} von ${liter(zielMl)} l'
          '${ml >= zielMl ? ' — Ziel erreicht' : ''}',
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (var i = 0; i < anzahl; i++)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: i < voll ? 'Glas ${i + 1} (voll)' : 'Glas ${i + 1}',
              // Das letzte volle Glas noch einmal antippen nimmt es zurück — für den
              // Fall, dass man sich vertippt hat.
              onPressed: () => onSet(i + 1 == voll ? i * glasMl : (i + 1) * glasMl),
              icon: Icon(
                i < voll ? Icons.local_drink : Icons.local_drink_outlined,
                color: i < voll ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _VorlagenName extends StatefulWidget {
  const _VorlagenName({required this.vorschlag});

  final String vorschlag;

  @override
  State<_VorlagenName> createState() => _VorlagenNameState();
}

class _VorlagenNameState extends State<_VorlagenName> {
  late final _feld = TextEditingController(text: widget.vorschlag);

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Als Vorlage speichern'),
        content: TextField(
          controller: _feld,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            helperText: 'Gleicher Name ersetzt die bisherige Vorlage',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _feld.text),
            child: const Text('Speichern'),
          ),
        ],
      );
}

/// Mit Vorzeichen: −350 heißt weniger gegessen als verbraucht.
String _bilanz(double v) {
  final r = v.round();
  return r > 0 ? '+$r kcal' : (r < 0 ? '−${-r} kcal' : '±0 kcal');
}

class _MahlzeitKarte extends StatelessWidget {
  const _MahlzeitKarte({
    required this.meal,
    required this.eintraege,
    required this.onAdd,
    required this.onChange,
    required this.onRemove,
    required this.onSaveTemplate,
  });

  final Meal meal;
  final List<MealEntry> eintraege;
  final VoidCallback onAdd;
  final void Function(MealEntry, double) onChange;
  final void Function(MealEntry) onRemove;
  final VoidCallback onSaveTemplate;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final summe = eintraege.fold<double>(0, (s, e) => s + e.kcal);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('${mealIcon(meal)} ${mealLabel(meal)}',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                if (summe > 0) Text('${summe.round()} kcal', style: grau),
                if (eintraege.isNotEmpty)
                  PopupMenuButton<void>(
                    tooltip: 'Mehr',
                    icon: const Icon(Icons.more_vert, size: 20),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        onTap: onSaveTemplate,
                        child: const ListTile(
                          leading: Icon(Icons.bookmark_add_outlined),
                          title: Text('Als Vorlage speichern'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                IconButton(
                  tooltip: '${mealLabel(meal)} hinzufügen',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            for (final e in eintraege)
              Dismissible(
                key: ValueKey(e),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: const Icon(Icons.delete_outline),
                ),
                onDismissed: (_) => onRemove(e),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(right: 8),
                  title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${e.grams.round()} g'
                    '${e.time.isEmpty ? '' : ' · ${e.time}'}',
                  ),
                  trailing: Text('${e.kcal.round()} kcal'),
                  onTap: () async {
                    final g = await askGrams(context, title: e.name, initial: e.grams);
                    if (g != null) onChange(e, g);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
