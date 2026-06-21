import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/auth/account_providers.dart';
import 'event_editor_sheet.dart';
import 'quick_entry.dart';

/// Aufgelöste Schnell-Eingabe inkl. Zielkalender.
class _QuickResult {
  const _QuickResult(this.entry, this.calendarHref);
  final QuickEntry entry;
  final String? calendarHref;
}

/// Schnell-Eingabe: Freitext wie „Zahnarzt morgen 15 Uhr Arbeit" → öffnet den
/// Termin-Editor mit vorausgefüllten Feldern (inkl. erkanntem Kalender).
Future<void> showQuickEntrySheet(BuildContext context) async {
  final result = await showModalBottomSheet<_QuickResult>(
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
  if (result == null || !context.mounted) return;
  await showEventEditor(
    context,
    initialTitle: result.entry.title,
    initialStart: result.entry.start,
    initialAllDay: result.entry.allDay,
    initialCalendarHref: result.calendarHref,
  );
}

class _QuickEntrySheet extends ConsumerStatefulWidget {
  const _QuickEntrySheet();

  @override
  ConsumerState<_QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends ConsumerState<_QuickEntrySheet> {
  final _ctrl = TextEditingController();
  final _speech = SpeechToText();
  String _text = '';
  bool _speechReady = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      final ok = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
      if (mounted) setState(() => _speechReady = ok);
    } catch (_) {
      if (mounted) setState(() => _speechReady = false);
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _ctrl.dispose();
    super.dispose();
  }

  /// Liste der beschreibbaren Termin-Kalender.
  List<dynamic> get _eventCalendars =>
      (ref.read(collectionsProvider).value ?? const [])
          .where((c) => c.supportsEvents)
          .toList();

  /// Parst den Text und löst den Zielkalender auf (erkannt → sonst „Persönlich").
  _QuickResult _resolve() {
    final cals = _eventCalendars;
    final names = cals.map((c) => c.displayName as String).toList();
    final entry = parseQuickEntry(_text, DateTime.now(), calendarNames: names);

    String? href;
    if (entry.calendarName != null) {
      href = _firstHrefWhere(
        cals,
        (n) => n.toLowerCase() == entry.calendarName!.toLowerCase(),
      );
    }
    // Fallback: „Persönlich"/„Personal" als Standard.
    href ??= _firstHrefWhere(
      cals,
      (n) =>
          n.toLowerCase().contains('persönlich') ||
          n.toLowerCase().contains('personal'),
    );
    return _QuickResult(entry, href);
  }

  String? _firstHrefWhere(List<dynamic> cals, bool Function(String) test) {
    for (final c in cals) {
      if (test(c.displayName as String)) return c.href as String;
    }
    return null;
  }

  String _calendarLabel(_QuickResult r) {
    final cals = _eventCalendars;
    for (final c in cals) {
      if (c.href == r.calendarHref) return c.displayName as String;
    }
    return 'Persönlich';
  }

  String _preview(_QuickResult r) {
    final e = r.entry;
    if (e.title.isEmpty) return 'Tippe z. B. „Zahnarzt morgen 15 Uhr"';
    final date = DateFormat('EEE, d. MMM', 'de_DE').format(e.start);
    final when = e.allDay
        ? '$date · Ganztägig'
        : '$date · ${DateFormat('HH:mm').format(e.start)}';
    return '📌 ${e.title}\n🗓️ $when\n🗂️ ${_calendarLabel(r)}';
  }

  Future<void> _toggleListen() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    if (!_speechReady) return;
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: 'de_DE'),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _text = result.recognizedWords;
          _ctrl.text = _text;
          _ctrl.selection = TextSelection.collapsed(offset: _text.length);
        });
      },
    );
  }

  void _submit() {
    final r = _resolve();
    if (r.entry.title.isEmpty) return;
    Navigator.pop(context, r);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _resolve();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Schnell-Eingabe', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Termin in einem Satz – Datum, Uhrzeit und Kalender werden erkannt.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Zahnarzt morgen 15 Uhr',
              prefixIcon: const Icon(Icons.bolt),
              border: const OutlineInputBorder(),
              suffixIcon: _speechReady
                  ? IconButton(
                      tooltip: _listening ? 'Stopp' : 'Sprechen',
                      icon: Icon(
                        _listening ? Icons.mic : Icons.mic_none,
                        color: _listening ? theme.colorScheme.error : null,
                      ),
                      onPressed: _toggleListen,
                    )
                  : null,
            ),
            onChanged: (v) => setState(() => _text = v),
            onSubmitted: (_) => _submit(),
          ),
          if (_listening)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '🎙️ Sprich jetzt…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
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
            child: Text(_preview(result), style: theme.textTheme.bodyMedium),
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
