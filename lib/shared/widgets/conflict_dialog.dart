import 'package:flutter/material.dart';

/// Ergebnis der Konflikt-Abfrage.
enum ConflictChoice { keepMine, loadServer }

/// Fragt bei einem Bearbeitungs-Konflikt (gleichzeitige Änderung), wie
/// verfahren werden soll. Gibt `null` zurück, wenn abgebrochen wurde.
Future<ConflictChoice?> showConflictDialog(BuildContext context) {
  return showDialog<ConflictChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.sync_problem),
      title: const Text('Konflikt'),
      content: const Text(
        'Dieser Eintrag wurde zwischenzeitlich an anderer Stelle geändert '
        '(z. B. auf einem anderen Gerät). Was möchtest du tun?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, ConflictChoice.loadServer),
          child: const Text('Aktuelle Version laden'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ConflictChoice.keepMine),
          child: const Text('Meine behalten'),
        ),
      ],
    ),
  );
}
