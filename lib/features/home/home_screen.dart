import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Startseite der App. Aktuell ein freundlicher Platzhalter – später kommt
/// hier ein Dashboard (heutige Termine, fällige Aufgaben, Einkauf auf einen
/// Blick).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Start')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.home_outlined,
                  size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Willkommen', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Hier entsteht deine Übersicht mit den heutigen Terminen, '
                'fälligen Aufgaben und dem Einkauf.\n\n'
                'Nutze unten die Tabs für Kalender, Aufgaben, Einkauf und '
                'Familie.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
