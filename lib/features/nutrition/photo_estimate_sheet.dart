import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'food_search_sheet.dart';
import 'nutrition_models.dart';
import 'nutrition_providers.dart';
import 'photo_estimate.dart';

/// Foto aufnehmen oder wählen, von Claude schätzen lassen, prüfen, eintragen.
///
/// Gibt `true` zurück, wenn etwas eingetragen wurde.
Future<bool> estimateFromPhoto(
  BuildContext context,
  WidgetRef ref, {
  required String date,
  required Meal meal,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final settings = ref.read(claudeSettingsProvider);
  final key = await settings.apiKey();
  if (key == null) {
    messenger.showSnackBar(const SnackBar(
      content: Text('Für die Foto-Erkennung erst einen Claude-API-Schlüssel eintragen: '
          'Einstellungen → Gesundheit → Foto-Erkennung.'),
    ));
    return false;
  }
  if (!context.mounted) return false;

  final quelle = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Foto aufnehmen'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Aus der Galerie'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (quelle == null) return false;

  // Verkleinert: Mehr als ~1500 Pixel Kantenlänge bringen der Schätzung nichts, kosten
  // aber Datenvolumen und Geld.
  final XFile? bild;
  try {
    bild = await ImagePicker().pickImage(
      source: quelle,
      maxWidth: 1568,
      maxHeight: 1568,
      imageQuality: 80,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Kein Foto: $e')));
    return false;
  }
  if (bild == null || !context.mounted) return false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Claude schätzt die Mahlzeit …')),
        ],
      ),
    ),
  );
  PhotoEstimate? schaetzung;
  String? fehler;
  try {
    schaetzung = await ref.read(claudePhotoClientProvider).estimate(
          apiKey: key,
          model: await settings.model(),
          jpeg: await bild.readAsBytes(),
        );
  } catch (e) {
    fehler = '$e';
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (!context.mounted) return false;
  if (fehler != null || schaetzung == null) {
    messenger.showSnackBar(SnackBar(content: Text(fehler ?? 'Keine Schätzung erhalten.')));
    return false;
  }
  if (schaetzung.items.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Auf dem Foto wurde kein Essen erkannt.')));
    return false;
  }

  final eintraege = await showModalBottomSheet<List<MealEntry>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PhotoReviewSheet(estimate: schaetzung!, meal: meal),
  );
  if (eintraege == null || eintraege.isEmpty) return false;
  await ref.read(nutritionProvider.notifier).addEntries(date, eintraege);
  return true;
}

/// Prüfliste zur Schätzung: abwählen, Mengen ändern, dann eintragen. Öffentlich für den
/// Widget-Test.
class PhotoReviewSheet extends StatefulWidget {
  const PhotoReviewSheet({super.key, required this.estimate, required this.meal});

  final PhotoEstimate estimate;
  final Meal meal;

  @override
  State<PhotoReviewSheet> createState() => _PhotoReviewSheetState();
}

class _PhotoReviewSheetState extends State<PhotoReviewSheet> {
  late final _an = List<bool>.filled(widget.estimate.items.length, true);
  late final _gramm = [for (final i in widget.estimate.items) i.grams];

  /// Mit der Menge wachsen alle Nährwerte im selben Verhältnis.
  MealEntry _eintrag(int i, String uhr) {
    final p = widget.estimate.items[i];
    final f = p.grams > 0 ? _gramm[i] / p.grams : 1.0;
    double? mal(double? v) => v == null ? null : v * f;
    return MealEntry(
      time: uhr,
      meal: widget.meal,
      name: '📷 ${p.name}',
      grams: _gramm[i],
      kcal: p.kcal * f,
      protein: mal(p.protein),
      carbs: mal(p.carbs),
      fat: mal(p.fat),
    );
  }

  Future<void> _menge(int i) async {
    final p = widget.estimate.items[i];
    final g = await askGrams(
      context,
      title: p.name,
      initial: _gramm[i],
      kcal100: p.grams > 0 ? p.kcal / p.grams * 100 : null,
    );
    if (g != null && g > 0) setState(() => _gramm[i] = g);
  }

  @override
  Widget build(BuildContext context) {
    final uhr = DateFormat('HH:mm').format(DateTime.now());
    final summe = [
      for (var i = 0; i < _an.length; i++)
        if (_an[i]) _eintrag(i, uhr).kcal,
    ].fold<double>(0, (a, b) => a + b);
    final grau = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Geschätzt — bitte prüfen',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (widget.estimate.hinweis.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(widget.estimate.hinweis, style: grau),
            ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < _an.length; i++)
                  CheckboxListTile(
                    value: _an[i],
                    onChanged: (v) => setState(() => _an[i] = v ?? false),
                    title: Text(widget.estimate.items[i].name),
                    subtitle: Text(
                      '${_gramm[i].round()} g · ${_eintrag(i, uhr).kcal.round()} kcal',
                    ),
                    secondary: IconButton(
                      tooltip: 'Menge ändern',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _menge(i),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: summe <= 0
                  ? null
                  : () => Navigator.pop(context, [
                        for (var i = 0; i < _an.length; i++)
                          if (_an[i]) _eintrag(i, uhr),
                      ]),
              child: Text('${summe.round()} kcal eintragen'),
            ),
          ),
        ],
      ),
    );
  }
}
