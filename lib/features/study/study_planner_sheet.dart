import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../calendar/event_providers.dart';
import '../members/member_settings.dart';
import 'study_planner.dart';
import 'study_settings.dart';
import 'study_windows_editor.dart';

/// Öffnet das Formular „Schularbeit & Lernplan".
Future<void> showStudyPlannerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: const _StudyPlannerSheet(),
    ),
  );
}

class _StudyPlannerSheet extends ConsumerStatefulWidget {
  const _StudyPlannerSheet();

  @override
  ConsumerState<_StudyPlannerSheet> createState() => _StudyPlannerSheetState();
}

class _StudyPlannerSheetState extends ConsumerState<_StudyPlannerSheet> {
  final _subject = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  StudyIntensity _intensity = StudyIntensity.mittel;
  String? _calHref; // gewählter Kalender (überschreibt den Standard)
  String? _person; // Schüler:in, für die die Arbeit ist
  bool _busy = false;

  Future<void> _addPerson() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Neue Person'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'z. B. Vincent',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(studyPersonsProvider.notifier).add(name);
    if (mounted) setState(() => _person = name);
  }

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      locale: const Locale('de'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _create(String? calHref) async {
    final fach = _subject.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (fach.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Bitte ein Fach/Thema angeben.')),
      );
      return;
    }
    if (calHref == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Bitte einen Kalender wählen.')),
      );
      return;
    }
    final windows = await ref.read(studyWindowsProvider.future);
    if (!mounted) return;
    if (!windows.any((w) => w.enabled)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte zuerst Lernzeiten festlegen (unten „Lernzeiten anpassen").',
          ),
        ),
      );
      return;
    }

    final sessions = planStudySessions(
      examDay: _date,
      targetDays: studyDaysFor(_intensity),
      windows: windows,
      notBefore: DateTime.now(),
    );

    setState(() => _busy = true);
    // Gewählten Kalender als Standard merken (nur Vorauswahl beim nächsten Mal).
    await ref.read(studyCalendarHrefProvider.notifier).set(calHref);
    final ctrl = ref.read(eventsControllerProvider.notifier);
    final dateStr = DateFormat('d. MMM', 'de_DE').format(_date);
    final person = _person?.trim();
    final examCats = [
      'Schularbeit',
      if (person != null && person.isNotEmpty) person,
    ];
    final learnCats = [
      'Lernen',
      if (person != null && person.isNotEmpty) person,
    ];
    try {
      await ctrl.createEvent(
        calendarHref: calHref,
        summary: '📝 Arbeit: $fach',
        start: DateTime(_date.year, _date.month, _date.day),
        allDay: true,
        categories: examCats,
      );
      final n = sessions.length;
      for (var i = 0; i < n; i++) {
        final s = sessions[i];
        await ctrl.createEvent(
          calendarHref: calHref,
          summary: '📚 Lernen: $fach (${i + 1}/$n)',
          start: s.start,
          end: s.end,
          description: 'Lernen für die Arbeit am $dateStr',
          categories: learnCats,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'Arbeit eingetragen – aber keine freien Lernzeiten vor dem '
                      'Termin gefunden.'
                : 'Lernplan erstellt: $n Lern-Einheit(en) + Arbeit am $dateStr.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('EEEE, d. MMMM y', 'de_DE').format(_date);
    final calendars = ref
        .watch(membersProvider)
        .where((m) => m.supportsEvents)
        .toList();
    // Vorauswahl: zuletzt gewählter Kalender, sonst Standard aus den Einstellungen.
    final defaultHref = ref.watch(studyCalendarHrefProvider).value;
    final selected = _calHref ?? defaultHref;
    final value = calendars.any((m) => m.href == selected) ? selected : null;
    final persons = ref.watch(studyPersonsProvider).value ?? const [];
    final personValue = (_person != null && persons.contains(_person))
        ? _person
        : null;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Schularbeit & Lernplan',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Die Lern-Einheiten werden automatisch in deinen Lernzeiten geplant.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _subject,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Fach / Thema',
                hintText: 'z. B. Mathe – Bruchrechnen',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Kalender (wohin wird gespeichert?)',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final m in calendars)
                  DropdownMenuItem(
                    value: m.href,
                    child: Row(
                      children: [
                        CircleAvatar(backgroundColor: m.color, radius: 7),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(m.name, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _calHref = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: personValue,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Für wen? (optional)',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in persons)
                  DropdownMenuItem(value: p, child: Text(p)),
                const DropdownMenuItem(
                  value: '__add__',
                  child: Text('＋ Neue Person …'),
                ),
              ],
              onChanged: (v) {
                if (v == '__add__') {
                  _addPerson();
                } else {
                  setState(() => _person = v);
                }
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Tag der Arbeit'),
              subtitle: Text(dateStr),
              trailing: TextButton(
                onPressed: _pickDate,
                child: const Text('Ändern'),
              ),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            Text(
              'Wie viel lernen?',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            SegmentedButton<StudyIntensity>(
              segments: const [
                ButtonSegment(value: StudyIntensity.kurz, label: Text('Kurz')),
                ButtonSegment(
                  value: StudyIntensity.mittel,
                  label: Text('Mittel'),
                ),
                ButtonSegment(value: StudyIntensity.viel, label: Text('Viel')),
              ],
              selected: {_intensity},
              onSelectionChanged: (s) => setState(() => _intensity = s.first),
            ),
            const SizedBox(height: 4),
            Text(
              '${studyDaysFor(_intensity)} Lern-Tage vor der Arbeit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            // Aufklappbares Menü: Lernzeiten direkt hier anpassen.
            Card(
              margin: EdgeInsets.zero,
              child: ExpansionTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Lernzeiten anpassen'),
                subtitle: const Text('Wochentage & Uhrzeiten'),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: const [StudyWindowsEditor()],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : () => _create(value),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: const Text('Lernplan erstellen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
