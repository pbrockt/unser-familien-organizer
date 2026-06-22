import 'package:flutter/material.dart';

/// Spickzettel mit allen Befehlen der Schnell-Eingabe.
Future<void> showQuickEntryHelp(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      Widget section(String title, List<(String, String)> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          for (final (cmd, desc) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(
                      text: '$cmd  ',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: desc,
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text(
              'Schnell-Eingabe – Befehle',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Alles in einem Satz – die App erkennt Datum, Uhrzeit, Kalender und '
              'mehr. Du bestätigst danach im Editor.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            section('Typ (am Anfang)', const [
              (
                'aufgabe:',
                'legt eine Aufgabe an, z. B. „aufgabe: Müll freitag"',
              ),
              ('einkauf:', 'fügt einen Artikel zur Einkaufsliste hinzu'),
              (
                'geburtstag:',
                '„geburtstag: Max 5.6.1990" (jährlich, mit Alter)',
              ),
              ('vorlage:', 'Termin zusätzlich als Vorlage speichern'),
            ]),
            section('Ziel-Kalender / Liste', const [
              ('Arbeit:', 'am Anfang → Kalender/Liste „Arbeit"'),
              ('… Arbeit', 'Kalendername auch als Wort im Satz'),
            ]),
            section('Datum', const [
              ('heute / morgen / übermorgen', ''),
              ('montag … sonntag', 'nächstes Vorkommen'),
              ('nächste Woche / nächsten Montag', ''),
              ('in 10 Tagen / in 2 Wochen / in 3 Monaten', ''),
              ('am Wochenende', 'nächster Samstag'),
              ('5.6. / 5.6.2026', 'festes Datum'),
            ]),
            section('Uhrzeit', const [
              ('15 Uhr / 15:30 / 15h', ''),
              ('14-16 Uhr / von 14 bis 16 Uhr', 'mit Ende'),
              ('für 2 Stunden / 90 min', 'Dauer'),
              ('halb 4', '= 15:30 (mit „nachmittags")'),
              ('morgens / mittags / nachmittags / abends', ''),
              ('ganztägig', 'als Ganztags-Termin'),
            ]),
            section('Serientermin', const [
              ('täglich / jede Woche / monatlich / jährlich', ''),
              ('jeden Montag', ''),
              ('alle 2 Wochen / alle 3 Tage', 'Intervall'),
              ('bis 31.12. / 10x', 'Ende der Serie'),
            ]),
            section('Extras', const [
              ('30 min vorher / 1 Tag vorher', 'Erinnerung'),
              ('@Praxis', 'Ort'),
            ]),
            const SizedBox(height: 16),
            Text(
              'Beispiel:',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '„Arbeit: Teammeeting jeden Montag 9-10 Uhr 15 min vorher"',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    },
  );
}
