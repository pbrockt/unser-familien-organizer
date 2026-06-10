import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_view.dart';

/// Kalender-Bereich (VEVENT per CalDAV).
///
/// Phase 4: Monats-/Wochen-/Agenda-Ansicht mit `table_calendar`,
/// Termine farbcodiert pro Familienmitglied, Serientermine (RRULE).
class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kalender')),
      body: const PlaceholderView(
        icon: Icons.calendar_month,
        title: 'Familienkalender',
        subtitle: 'Termine aller Familienmitglieder.\n'
            'Phase 4: VEVENT-Sync per CalDAV mit Nextcloud.',
      ),
    );
  }
}
