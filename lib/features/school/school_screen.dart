import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_providers.dart';
import '../calendar/calendar_event.dart';
import '../calendar/event_actions.dart';
import '../calendar/event_providers.dart';
import '../study/study_planner_sheet.dart';
import 'exam_detail_screen.dart';
import 'school_logic.dart';

/// „Schule"-Tab: listet anstehende Schularbeiten – gruppiert nach Person.
/// Datenquelle sind die Lernplaner-Termine (📝 Arbeit) im Kalender.
class SchoolScreen extends ConsumerWidget {
  const SchoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    final events = ref.watch(visibleEventsProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = groupExamsByPerson(events, today);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Schule'),
        actions: [
          IconButton(
            tooltip: 'Schularbeit anlegen',
            icon: const Icon(Icons.add),
            onPressed: () => showStudyPlannerSheet(context),
          ),
        ],
      ),
      body: account == null
          ? const _Hint(
              'Verbinde dich mit der Nextcloud, um Schularbeiten zu '
              'sehen.',
            )
          : groups.isEmpty
          ? _EmptySchool(onAdd: () => showStudyPlannerSheet(context))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final g in groups) ...[
                  _PersonHeader(person: g.person, count: g.exams.length),
                  for (final exam in g.exams)
                    _ExamTile(
                      exam: exam,
                      today: today,
                      sessions: plannedSessions(events, exam, now),
                      // Tippen → Lern-Tage-Übersicht (abhaken); lange drücken →
                      // schnell im Kalender öffnen / bearbeiten.
                      onOpen: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ExamDetailScreen(examUid: exam.uid),
                        ),
                      ),
                      onLongPress: () => showEventActions(context, ref, exam),
                    ),
                ],
              ],
            ),
    );
  }
}

class _PersonHeader extends StatelessWidget {
  const _PersonHeader({required this.person, required this.count});
  final String person;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          const Icon(Icons.person, size: 18),
          const SizedBox(width: 8),
          Text(
            person,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            count == 1 ? '1 Arbeit' : '$count Arbeiten',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamTile extends StatelessWidget {
  const _ExamTile({
    required this.exam,
    required this.today,
    required this.sessions,
    required this.onOpen,
    required this.onLongPress,
  });
  final CalendarEvent exam;
  final DateTime today;
  final int sessions;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;

  String _countdown() {
    final d = DateTime(exam.start.year, exam.start.month, exam.start.day);
    final days = d.difference(today).inDays;
    if (days <= 0) return 'heute';
    if (days == 1) return 'morgen';
    return 'in $days Tagen';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = exam.color ?? theme.colorScheme.primary;
    final date = DateFormat('EEE, d. MMM', 'de_DE').format(exam.start);
    final soon =
        DateTime(
          exam.start.year,
          exam.start.month,
          exam.start.day,
        ).difference(today).inDays <=
        2;
    return ListTile(
      leading: CircleAvatar(radius: 6, backgroundColor: color),
      title: Text(
        subjectOf(exam.summary),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$date · ${_countdown()}'
        '${sessions > 0 ? ' · $sessions Lern-Einheiten' : ''}',
        style: TextStyle(
          color: soon
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onOpen,
      onLongPress: onLongPress,
    );
  }
}

class _EmptySchool extends StatelessWidget {
  const _EmptySchool({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.school_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Keine anstehenden Arbeiten',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Lege eine Schularbeit an – die Lern-Einheiten werden automatisch '
              'im Kalender geplant und hier je Person aufgelistet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Schularbeit anlegen'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(text, textAlign: TextAlign.center),
    ),
  );
}
