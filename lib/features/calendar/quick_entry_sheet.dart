import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'event_editor_sheet.dart';
import 'quick_entry.dart';

/// Schnell-Eingabe: Freitext wie „Zahnarzt morgen 15 Uhr" → öffnet den
/// Termin-Editor mit vorausgefüllten Feldern zur Bestätigung.
Future<void> showQuickEntrySheet(BuildContext context) async {
  final entry = await showModalBottomSheet<QuickEntry>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: const _QuickEntrySheet(),
    ),
  );
  if (entry == null || !context.mounted) return;
  await showEventEditor(
    context,
    initialTitle: entry.title,
    initialStart: entry.start,
    initialAllDay: entry.allDay,
  );
}

class _QuickEntrySheet extends StatefulWidget {
  const _QuickEntrySheet();

  @override
  State<_QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends State<_QuickEntrySheet> {
  final _ctrl = TextEditingController();
  String _text = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _preview() {
    final e = parseQuickEntry(_text, DateTime.now());
    if (e.title.isEmpty) return 'Tippe z. B. „Zahnarzt morgen 15 Uhr"';
    final date = DateFormat('EEE, d. MMM', 'de_DE').format(e.start);
    final when = e.allDay
        ? '$date · Ganztägig'
        : '$date · ${DateFormat('HH:mm').format(e.start)}';
    return '📌 ${e.title}\n🗓️ $when';
  }

  void _submit() {
    final e = parseQuickEntry(_text, DateTime.now());
    if (e.title.isEmpty) return;
    Navigator.pop(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Schnell-Eingabe', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Termin in einem Satz – Datum & Uhrzeit werden automatisch erkannt.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Zahnarzt morgen 15 Uhr',
              prefixIcon: Icon(Icons.bolt),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _text = v),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_preview(), style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _text.trim().isEmpty ? null : _submit,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Weiter zum Termin'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
