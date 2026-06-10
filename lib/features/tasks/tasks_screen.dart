import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_view.dart';

/// Aufgaben-Bereich (VTODO per CalDAV).
///
/// Phase 5: Aufgabenlisten, Abhaken (STATUS:COMPLETED), Unteraufgaben
/// (RELATED-TO), Priorität und Fälligkeitsdatum.
class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aufgaben')),
      body: const PlaceholderView(
        icon: Icons.check_circle,
        title: 'Aufgaben',
        subtitle: 'Wer macht was?\n'
            'Phase 5: VTODO-Sync per CalDAV mit Nextcloud.',
      ),
    );
  }
}
