import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';

/// Farbauswahl beim Anlegen (Markenpalette + ein paar Ergänzungen).
const _palette = <String>[
  '#E8964F',
  '#A9C29B',
  '#AFC6DD',
  '#D89B79',
  '#D9785A',
  '#7E9CBE',
  '#B07BAC',
  '#5BA199',
];

enum _NewType { calendar, tasks }

/// Öffnet das Sheet zum Anlegen eines neuen Kalenders/einer neuen Liste.
/// Gibt `true` zurück, wenn etwas angelegt wurde.
Future<bool?> showNewCalendarSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: const _NewCalendarSheet(),
    ),
  );
}

class _NewCalendarSheet extends ConsumerStatefulWidget {
  const _NewCalendarSheet();

  @override
  ConsumerState<_NewCalendarSheet> createState() => _NewCalendarSheetState();
}

class _NewCalendarSheetState extends ConsumerState<_NewCalendarSheet> {
  final _nameCtrl = TextEditingController();
  _NewType _type = _NewType.calendar;
  String _color = _palette.first;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Bitte einen Namen eingeben.');
      return;
    }
    final account = ref.read(accountProvider).value;
    if (account == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(caldavClientProvider).createCalendar(
            account,
            displayName: name,
            events: _type == _NewType.calendar,
            todos: _type == _NewType.tasks,
            color: _color,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.add_circle_outline),
                const SizedBox(width: 12),
                Text('Neuer Kalender / Liste',
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'z.B. Familie, Arbeit, Einkauf',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<_NewType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _NewType.calendar,
                  label: Text('Kalender'),
                  icon: Icon(Icons.event),
                ),
                ButtonSegment(
                  value: _NewType.tasks,
                  label: Text('Aufgabenliste'),
                  icon: Icon(Icons.checklist),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            Text('Farbe', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final hex in _palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = hex),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(
                            int.parse('FF${hex.substring(1)}', radix: 16)),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == hex
                              ? theme.colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _color == hex
                          ? const Icon(Icons.check,
                              size: 18, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_busy ? 'Wird angelegt…' : 'Anlegen'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
