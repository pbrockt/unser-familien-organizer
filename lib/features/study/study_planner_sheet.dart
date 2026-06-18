import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../calendar/event_providers.dart';
import 'study_planner.dart';
import 'study_settings.dart';

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
  bool _busy = false;

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

  Future<void> _create() async {
    final fach = _subject.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (fach.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Bitte ein Fach/Thema angeben.')),
      );
      return;
    }
    final calHref = await ref.read(studyCalendarHrefProvider.future);
    final windows = await ref.read(studyWindowsProvider.future);
    if (!mounted) return;
    if (calHref == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte zuerst in Einstellungen → Lernen einen Lern-Kalender wählen.',
          ),
        ),
      );
      return;
    }
    if (!windows.any((w) => w.enabled)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte zuerst Lernzeiten festlegen (Einstellungen → Lernen).',
          ),
        ),
      );
      return;
    }

    final today = DateTime.now();
    final sessions = planStudySessions(
      examDay: _date,
      targetDays: studyDaysFor(_intensity),
      windows: windows,
      notBefore: today,
    );

    setState(() => _busy = true);
    final ctrl = ref.read(eventsControllerProvider.notifier);
    final dateStr = DateFormat('d. MMM', 'de_DE').format(_date);
    try {
      // Die Arbeit selbst (ganztägig).
      await ctrl.createEvent(
        calendarHref: calHref,
        summary: '📝 Arbeit: $fach',
        start: DateTime(_date.year, _date.month, _date.day),
        allDay: true,
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
    return SafeArea(
      child: Padding(
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
              'Lege die Arbeit an – die Lern-Einheiten werden automatisch in '
              'deinen Lernzeiten geplant.',
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
            const SizedBox(height: 6),
            Text(
              '${studyDaysFor(_intensity)} Lern-Tage vor der Arbeit',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _create,
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
