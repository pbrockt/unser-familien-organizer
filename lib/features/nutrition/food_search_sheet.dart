import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/platform/platform_support.dart';
import 'barcode_scan_screen.dart';
import 'nutrition_models.dart';
import 'nutrition_providers.dart';
import 'photo_estimate_sheet.dart';

/// Öffnet die Suche und trägt das gewählte Lebensmittel in [meal] an [date] ein.
Future<void> showFoodSearch(
  BuildContext context, {
  required String date,
  required Meal meal,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FoodSearchSheet(date: date, meal: meal),
    );

/// Fragt die Menge in Gramm ab. Mit [portionG] gibt es einen Knopf für eine Portion.
Future<double?> askGrams(
  BuildContext context, {
  required String title,
  double initial = 100,
  double? portionG,
  double? kcal100,
}) =>
    showDialog<double>(
      context: context,
      builder: (_) => _MengenDialog(
        title: title,
        initial: initial,
        portionG: portionG,
        kcal100: kcal100,
      ),
    );

class _FoodSearchSheet extends ConsumerStatefulWidget {
  const _FoodSearchSheet({required this.date, required this.meal});

  final String date;
  final Meal meal;

  @override
  ConsumerState<_FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends ConsumerState<_FoodSearchSheet> {
  final _text = TextEditingController();
  Timer? _verzoegerung;
  List<Food> _online = const [];
  bool _sucht = false;
  String? _fehler;

  @override
  void dispose() {
    _verzoegerung?.cancel();
    _text.dispose();
    super.dispose();
  }

  /// Erst tippen lassen, dann fragen: Open Food Facts begrenzt die Suchanfragen, und
  /// jeder Buchstabe eine Anfrage wäre nach wenigen Wörtern gesperrt.
  void _beiEingabe(String t) {
    _verzoegerung?.cancel();
    setState(() {});
    if (t.trim().length < 3) {
      setState(() => _online = const []);
      return;
    }
    _verzoegerung = Timer(const Duration(milliseconds: 600), () => _suche(t.trim()));
  }

  Future<void> _suche(String t) async {
    setState(() {
      _sucht = true;
      _fehler = null;
    });
    try {
      final r = await ref.read(offClientProvider).search(t);
      if (mounted && _text.text.trim() == t) setState(() => _online = r);
    } catch (e) {
      if (mounted) setState(() => _fehler = '$e');
    } finally {
      if (mounted) setState(() => _sucht = false);
    }
  }

  Future<void> _waehle(Food f) async {
    final g = await askGrams(
      context,
      title: f.label,
      initial: f.portionG ?? 100,
      portionG: f.portionG,
      kcal100: f.kcal100,
    );
    if (g == null || !mounted) return;
    final jetzt = DateTime.now();
    final entry = f.portion(
      grams: g,
      meal: widget.meal,
      time: DateFormat('HH:mm').format(jetzt),
    );
    await ref.read(nutritionProvider.notifier).add(widget.date, f, entry);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _foto() async {
    final ok = await estimateFromPhoto(
      context,
      ref,
      date: widget.date,
      meal: widget.meal,
    );
    if (ok && mounted) Navigator.of(context).pop();
  }

  Future<void> _vorlage(MealTemplate t) async {
    await ref.read(nutritionProvider.notifier).applyTemplate(
          widget.date,
          widget.meal,
          t,
          DateFormat('HH:mm').format(DateTime.now()),
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _vorlageLoeschen(MealTemplate t) async {
    final ja = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('„${t.name}" löschen?'),
        content: const Text('Bereits eingetragene Mahlzeiten bleiben erhalten.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ja == true) await ref.read(nutritionProvider.notifier).deleteTemplate(t);
  }

  Future<void> _eigenes({String? barcode}) async {
    final f = await showDialog<Food>(
      context: context,
      builder: (_) => _EigenesDialog(name: _text.text.trim(), barcode: barcode),
    );
    if (f != null) await _waehle(f);
  }

  /// Scannen → erst „Meine Lebensmittel", dann Open Food Facts, sonst selbst anlegen.
  Future<void> _scannen() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code == null || !mounted) return;

    final bekannt = ref.read(nutritionProvider).value?.foods[code];
    if (bekannt != null) {
      await _waehle(bekannt);
      return;
    }
    setState(() {
      _sucht = true;
      _fehler = null;
    });
    Food? gefunden;
    try {
      gefunden = await ref.read(offClientProvider).byBarcode(code);
    } catch (e) {
      if (mounted) setState(() => _fehler = '$e');
      return;
    } finally {
      if (mounted) setState(() => _sucht = false);
    }
    if (!mounted) return;
    if (gefunden != null) {
      await _waehle(gefunden);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Barcode $code ist bei Open Food Facts unbekannt — bitte die '
            'Werte von der Packung eintragen.'),
      ));
      await _eigenes(barcode: code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final daten = ref.watch(nutritionProvider).value;
    final suchtext = _text.text.trim().toLowerCase();
    final bekannt = suchtext.isEmpty
        ? (daten?.recentFoods() ?? const <Food>[])
        : (daten?.foods.values
                .where((f) => f.label.toLowerCase().contains(suchtext))
                .take(10)
                .toList() ??
            const <Food>[]);
    final bekannteIds = bekannt.map((f) => f.id).toSet();
    final vorlagen = (daten?.activeTemplates ?? const <MealTemplate>[])
        .where((t) => suchtext.isEmpty || t.name.toLowerCase().contains(suchtext))
        .toList();
    final online = _online.where((f) => !bekannteIds.contains(f.id)).toList();
    final grau = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _text,
                autofocus: true,
                onChanged: _beiEingabe,
                decoration: InputDecoration(
                  hintText: '${mealLabel(widget.meal)}: Lebensmittel suchen',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _sucht
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : (isAndroid
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Foto schätzen lassen',
                                  onPressed: _foto,
                                  icon: const Icon(Icons.photo_camera_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Barcode scannen',
                                  onPressed: _scannen,
                                  icon: const Icon(Icons.qr_code_scanner),
                                ),
                              ],
                            )
                          : null),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (vorlagen.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('MEINE VORLAGEN', style: grau),
                    ),
                    for (final t in vorlagen)
                      ListTile(
                        leading: const Icon(Icons.bookmark_outline),
                        title: Text(t.name),
                        subtitle: Text(
                          '${t.items.length} Lebensmittel · ${t.kcal.round()} kcal',
                        ),
                        onTap: () => _vorlage(t),
                        onLongPress: () => _vorlageLoeschen(t),
                      ),
                  ],
                  if (bekannt.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        suchtext.isEmpty ? 'ZULETZT GEGESSEN' : 'MEINE LEBENSMITTEL',
                        style: grau,
                      ),
                    ),
                    for (final f in bekannt) _FoodTile(food: f, onTap: () => _waehle(f)),
                  ],
                  if (online.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text('OPEN FOOD FACTS', style: grau),
                    ),
                    for (final f in online) _FoodTile(food: f, onTap: () => _waehle(f)),
                  ],
                  if (_fehler != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_fehler!),
                    ),
                  if (suchtext.isNotEmpty &&
                      suchtext.length < 3 &&
                      bekannt.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Ab drei Buchstaben wird online gesucht.'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.edit_note),
                    title: const Text('Eigenes Lebensmittel anlegen'),
                    subtitle: const Text('Für Selbstgekochtes oder was nicht gefunden wird'),
                    onTap: _eigenes,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food, required this.onTap});

  final Food food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final makros = [
      if (food.protein100 != null) 'E ${food.protein100!.round()}',
      if (food.carbs100 != null) 'K ${food.carbs100!.round()}',
      if (food.fat100 != null) 'F ${food.fat100!.round()}',
    ].join(' · ');
    return ListTile(
      title: Text(food.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (food.brand != null) food.brand!,
          '${food.kcal100.round()} kcal/100 g',
          if (makros.isNotEmpty) makros,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

class _MengenDialog extends StatefulWidget {
  const _MengenDialog({
    required this.title,
    required this.initial,
    this.portionG,
    this.kcal100,
  });

  final String title;
  final double initial;
  final double? portionG;
  final double? kcal100;

  @override
  State<_MengenDialog> createState() => _MengenDialogState();
}

class _MengenDialogState extends State<_MengenDialog> {
  late final _feld = TextEditingController(text: _zahl(widget.initial));

  static String _zahl(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).replaceAll('.', ',');

  double? get _gramm => double.tryParse(_feld.text.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _feld.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = _gramm;
    final gueltig = g != null && g > 0 && g <= 5000;
    return AlertDialog(
      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _feld,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              suffixText: 'g',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              if (widget.portionG != null)
                ActionChip(
                  label: Text('1 Portion (${_zahl(widget.portionG!)} g)'),
                  onPressed: () => setState(() => _feld.text = _zahl(widget.portionG!)),
                ),
              for (final v in const [50.0, 100.0, 150.0, 250.0])
                ActionChip(
                  label: Text('${v.round()} g'),
                  onPressed: () => setState(() => _feld.text = _zahl(v)),
                ),
            ],
          ),
          if (widget.kcal100 != null && gueltig) ...[
            const SizedBox(height: 8),
            Text('= ${(widget.kcal100! * g / 100).round()} kcal'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: gueltig ? () => Navigator.pop(context, g) : null,
          child: const Text('Übernehmen'),
        ),
      ],
    );
  }
}

/// Eigenes Lebensmittel: Name und Nährwerte je 100 g, wie sie auf der Packung stehen.
class _EigenesDialog extends StatefulWidget {
  const _EigenesDialog({required this.name, this.barcode});

  final String name;

  /// Gescannt, aber unbekannt: Dann wird der Barcode die Kennung, und beim nächsten
  /// Scan ist das Produkt gleich da.
  final String? barcode;

  @override
  State<_EigenesDialog> createState() => _EigenesDialogState();
}

class _EigenesDialogState extends State<_EigenesDialog> {
  late final _name = TextEditingController(text: widget.name);
  final _kcal = TextEditingController();
  final _eiweiss = TextEditingController();
  final _kh = TextEditingController();
  final _fett = TextEditingController();
  final _portion = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _kcal, _eiweiss, _kh, _fett, _portion]) {
      c.dispose();
    }
    super.dispose();
  }

  static double? _wert(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Widget _feld(TextEditingController c, String label, String einheit) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            suffixText: einheit,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    final kcal = _wert(_kcal);
    final gueltig = name.isNotEmpty && kcal != null && kcal >= 0 && kcal <= 1000;
    return AlertDialog(
      title: const Text('Eigenes Lebensmittel'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            _feld(_kcal, 'Brennwert je 100 g', 'kcal'),
            _feld(_eiweiss, 'Eiweiß je 100 g', 'g'),
            _feld(_kh, 'Kohlenhydrate je 100 g', 'g'),
            _feld(_fett, 'Fett je 100 g', 'g'),
            _feld(_portion, 'Übliche Portion (optional)', 'g'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: !gueltig
              ? null
              : () => Navigator.pop(
                    context,
                    Food(
                      id: widget.barcode ?? 'eigen:${name.toLowerCase()}',
                      barcode: widget.barcode,
                      name: name,
                      kcal100: kcal,
                      protein100: _wert(_eiweiss),
                      carbs100: _wert(_kh),
                      fat100: _wert(_fett),
                      portionG: _wert(_portion),
                      source: 'eigen',
                      updated: DateTime.now(),
                    ),
                  ),
          child: const Text('Weiter'),
        ),
      ],
    );
  }
}
