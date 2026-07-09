import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_providers.dart';
import '../calendar/calendar_event.dart';
import '../calendar/event_actions.dart';
import '../calendar/event_providers.dart';
import '../members/user_groups.dart';
import 'school_logic.dart';

/// Detail einer Schularbeit: listet die geplanten Lern-Tage auf. Der
/// zugewiesene Nutzer (bzw. ein Eltern-Gerät) kann pro Tag abhaken, ob gelernt
/// wurde – ähnlich wie eine Aufgabenliste.
class ExamDetailScreen extends ConsumerWidget {
  const ExamDetailScreen({super.key, required this.examUid});

  /// UID der Arbeit – damit wir nach Änderungen immer den frischen Termin lesen.
  final String examUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(visibleEventsProvider);
    final account = ref.watch(accountProvider).value;
    // Eltern-Rechte: manueller Geräte-Schalter ODER Mitglied der Eltern-Gruppe.
    final parentMode = ref.watch(effectiveParentModeProvider);

    CalendarEvent? exam;
    for (final e in events) {
      if (e.uid == examUid && isExam(e)) {
        exam = e;
        break;
      }
    }
    if (exam == null) {
      // Arbeit wurde gelöscht o. Ä. → zurück.
      return Scaffold(
        appBar: AppBar(title: const Text('Schularbeit')),
        body: const Center(child: Text('Diese Arbeit gibt es nicht mehr.')),
      );
    }

    final person = personOf(exam);
    final sessions = studySessionsFor(events, exam);
    final doneCount = sessions.where(isSessionDone).length;
    final canCheck = canCheckStudy(
      assignedPerson: person,
      username: account?.username,
      parentMode: parentMode,
    );
    final canEdit = canEditStudy(parentMode: parentMode);
    final subject = subjectOf(exam.summary);
    final examDate = DateFormat('EEEE, d. MMMM y', 'de_DE').format(exam.start);

    Future<void> toggle(CalendarEvent session, bool done) async {
      await ref
          .read(eventsControllerProvider.notifier)
          .setEventCategories(session, sessionCategoriesToggled(session, done));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(subject),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Bearbeiten',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showEventActions(context, ref, exam!),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _Header(
            subject: subject,
            person: person,
            examDate: examDate,
            doneCount: doneCount,
            total: sessions.length,
          ),
          if (!canCheck)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                person == kNoPerson
                    ? 'Zum Abhaken bitte eine Person zuweisen.'
                    : 'Nur $person (oder ein Eltern-Gerät) kann diese '
                          'Lern-Tage abhaken.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Für diese Arbeit sind keine Lern-Einheiten geplant.',
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final s in sessions)
              _SessionTile(
                session: s,
                enabled: canCheck,
                onChanged: canCheck ? (v) => toggle(s, v) : null,
              ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.subject,
    required this.person,
    required this.examDate,
    required this.doneCount,
    required this.total,
  });
  final String subject;
  final String person;
  final String examDate;
  final int doneCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = total == 0 ? 0.0 : doneCount / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subject, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.event, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  examDate,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (person != kNoPerson)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    person,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: progress, minHeight: 8),
            ),
            const SizedBox(height: 4),
            Text(
              '$doneCount von $total Lern-Tagen gelernt',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text('Lern-Tage', style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.enabled,
    required this.onChanged,
  });
  final CalendarEvent session;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final done = isSessionDone(session);
    final date = DateFormat('EEEE, d. MMM', 'de_DE').format(session.start);
    final time = session.allDay
        ? null
        : '${DateFormat('HH:mm').format(session.start)}'
              '${session.end != null ? '–${DateFormat('HH:mm').format(session.end!)}' : ''} Uhr';
    return CheckboxListTile(
      value: done,
      onChanged: enabled ? (v) => onChanged?.call(v ?? false) : null,
      title: Text(
        date,
        style: TextStyle(decoration: done ? TextDecoration.lineThrough : null),
      ),
      subtitle: time == null ? null : Text(time),
      secondary: Icon(
        done ? Icons.check_circle : Icons.menu_book_outlined,
        color: done ? Theme.of(context).colorScheme.primary : null,
      ),
    );
  }
}
