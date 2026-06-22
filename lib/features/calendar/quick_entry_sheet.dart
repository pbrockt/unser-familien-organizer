import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/auth/account_providers.dart';
import '../tasks/task_editor_sheet.dart';
import '../tasks/task_item.dart';
import '../tasks/task_providers.dart';
import 'birthdays.dart';
import 'event_editor_sheet.dart';
import 'quick_entry.dart';
import 'quick_entry_help.dart';

/// Schnell-Eingabe: Freitext wie „Zahnarzt morgen 15 Uhr Arbeit" → erkennt Typ,
/// Datum, Uhrzeit, Serie, Kalender/Liste, Erinnerung … und öffnet danach den
/// passenden Editor (bzw. fügt Einkaufsartikel direkt hinzu).
Future<void> showQuickEntrySheet(BuildContext context, WidgetRef ref) async {
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

  switch (entry.kind) {
    case QuickKind.shopping:
      await _addShopping(context, ref, entry.title);
    case QuickKind.task:
      final lists =
          ref.read(tasksControllerProvider).value ?? const <TaskList>[];
      await showTaskEditor(
        context,
        lists: lists,
        initialTitle: entry.title,
        initialDue: entry.allDay
            ? DateTime(entry.start.year, entry.start.month, entry.start.day)
            : entry.start,
        initialListHref: _matchHref(
          lists.map((l) => (l.href, l.name)),
          entry.targetName,
        ),
        initialRepeat: _repeatKey(entry.rrule),
      );
    case QuickKind.event:
    case QuickKind.birthday:
      await showEventEditor(
        context,
        initialTitle: entry.title,
        initialStart: entry.start,
        initialEnd: entry.end,
        initialAllDay: entry.allDay,
        initialCalendarHref: _eventCalendarHref(ref, entry),
        initialRrule: entry.rrule,
        initialReminderMinutes: entry.reminderMinutes,
        initialSaveAsTemplate: entry.saveAsTemplate,
        initialLocation: entry.location,
      );
  }
}

/// Zielkalender für Termin/Geburtstag: erkannter Kalender → bei Geburtstag der
/// gewählte Geburtstags-Kalender → sonst „Persönlich".
String? _eventCalendarHref(WidgetRef ref, QuickEntry entry) {
  final cals = (ref.read(collectionsProvider).value ?? const [])
      .where((c) => c.supportsEvents)
      .toList();
  Iterable<(String, String)> pairs() =>
      cals.map((c) => (c.href, c.displayName));

  final matched = _matchHref(pairs(), entry.targetName);
  if (matched != null) return matched;

  if (entry.kind == QuickKind.birthday) {
    final cfg = ref.read(birthdayConfigProvider).value;
    if (cfg?.calendarHref != null && cfg!.calendarHref!.isNotEmpty) {
      return cfg.calendarHref;
    }
  }
  // Fallback „Persönlich".
  for (final c in cals) {
    final n = c.displayName.toLowerCase();
    if (n.contains('persönlich') || n.contains('personal')) {
      return c.href;
    }
  }
  return null;
}

/// Sucht den href, dessen Name [name] (case-insensitive) entspricht.
String? _matchHref(Iterable<(String href, String name)> items, String? name) {
  if (name == null) return null;
  final lower = name.toLowerCase();
  for (final it in items) {
    if (it.$2.toLowerCase() == lower) return it.$1;
  }
  return null;
}

String _repeatKey(String? rrule) {
  if (rrule == null) return 'none';
  final up = rrule.toUpperCase();
  final freq = RegExp(r'FREQ=([A-Z]+)').firstMatch(up)?.group(1);
  final interval = RegExp(r'INTERVAL=(\d+)').firstMatch(up)?.group(1);
  return switch (freq) {
    'DAILY' => 'DAILY',
    'WEEKLY' => interval == '2' ? 'BIWEEKLY' : 'WEEKLY',
    'MONTHLY' => 'MONTHLY',
    'YEARLY' => 'YEARLY',
    _ => 'none',
  };
}

/// Fügt einen Artikel direkt zur Einkaufsliste hinzu (Pref-Wahl, sonst Liste
/// mit „Einkauf"/„Shopping" im Namen, sonst erste Liste).
Future<void> _addShopping(
  BuildContext context,
  WidgetRef ref,
  String item,
) async {
  if (item.isEmpty) return;
  final lists = ref.read(tasksControllerProvider).value ?? const <TaskList>[];
  if (lists.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keine Einkaufsliste vorhanden.')),
      );
    }
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('shopping_list_href');
  String href = lists.first.href;
  if (saved != null && lists.any((l) => l.href == saved)) {
    href = saved;
  } else {
    for (final l in lists) {
      final n = l.name.toLowerCase();
      if (n.contains('einkauf') || n.contains('shopping')) {
        href = l.href;
        break;
      }
    }
  }
  await ref
      .read(tasksControllerProvider.notifier)
      .createTask(listHref: href, summary: item);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('„$item" zur Einkaufsliste hinzugefügt')),
    );
  }
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

  List<String> get _calendarNames =>
      (ref.read(collectionsProvider).value ?? const [])
          .where((c) => c.supportsEvents)
          .map((c) => c.displayName)
          .toList();

  List<String> get _listNames =>
      (ref.read(tasksControllerProvider).value ?? const <TaskList>[])
          .map((l) => l.name)
          .toList();

  QuickEntry _parse() => parseQuickEntry(
    _text,
    DateTime.now(),
    calendarNames: _calendarNames,
    listNames: _listNames,
  );

  String _kindLabel(QuickKind k) => switch (k) {
    QuickKind.task => '✅ Aufgabe',
    QuickKind.shopping => '🛒 Einkauf',
    QuickKind.birthday => '🎂 Geburtstag',
    QuickKind.event => '🗓️ Termin',
  };

  String _preview(QuickEntry e) {
    if (e.title.isEmpty) return 'Tippe z. B. „Zahnarzt morgen 15 Uhr"';
    final lines = <String>['${_kindLabel(e.kind)}: ${e.title}'];
    if (e.kind != QuickKind.shopping) {
      final date = DateFormat('EEE, d. MMM', 'de_DE').format(e.start);
      var when = e.allDay
          ? '$date · Ganztägig'
          : '$date · ${DateFormat('HH:mm').format(e.start)}';
      if (e.end != null) {
        when = '$when–${DateFormat('HH:mm').format(e.end!)}';
      }
      lines.add('🗓️ $when');
      if (e.rrule != null) lines.add('🔁 wiederkehrend');
      if (e.targetName != null) lines.add('🗂️ ${e.targetName}');
      if (e.reminderMinutes != null) lines.add('🔔 Erinnerung');
      if (e.location != null) lines.add('📍 ${e.location}');
    }
    return lines.join('\n');
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
    final e = _parse();
    if (e.title.isEmpty) return;
    Navigator.pop(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = _parse();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Schnell-Eingabe',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => showQuickEntryHelp(context),
                icon: const Icon(Icons.help_outline, size: 18),
                label: const Text('Befehle'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Termin/Aufgabe/Einkauf/Geburtstag in einem Satz – wird automatisch '
            'erkannt.',
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
            child: Text(_preview(entry), style: theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _text.trim().isEmpty ? null : _submit,
            icon: Icon(
              entry.kind == QuickKind.shopping
                  ? Icons.add_shopping_cart
                  : Icons.arrow_forward,
            ),
            label: Text(
              entry.kind == QuickKind.shopping ? 'Zur Einkaufsliste' : 'Weiter',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}
