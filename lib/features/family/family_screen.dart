import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_view.dart';

/// Familien-Bereich: Mitglieder, Farbzuordnung, Nextcloud-Verbindung.
///
/// Phase 3/7: Nextcloud-Login (Login Flow v2), Familienmitglieder mit
/// eigenen Farben, geteilte Kalender-/Listen-Auswahl.
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Familie')),
      body: const PlaceholderView(
        icon: Icons.people,
        title: 'Familie & Verbindung',
        subtitle: 'Nextcloud verbinden, Mitglieder & Farben verwalten.\n'
            'Phase 3: Nextcloud Login Flow v2.',
      ),
    );
  }
}
