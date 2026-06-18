import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../family/share_calendar_sheet.dart';
import '../members/member_settings.dart';
import 'study_settings.dart';

/// Einstellungen rund ums Lernen: erlaubte Lernzeiten je Wochentag und der
/// Kalender, in den die generierten Lern-Termine geschrieben werden.
class StudySettingsScreen extends ConsumerWidget {
  const StudySettingsScreen({super.key});

  static const _dayNames = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _editTime(
    BuildContext context,
    WidgetRef ref,
    int i,
    StudyWindow w,
  ) async {
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: w.startMinute ~/ 60,
        minute: w.startMinute % 60,
      ),
      helpText: 'Lernen ab',
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: w.endMinute ~/ 60, minute: w.endMinute % 60),
      helpText: 'Lernen bis',
    );
    if (end == null) return;
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    await ref
        .read(studyWindowsProvider.notifier)
        .setDay(
          i,
          w.copyWith(
            enabled: true,
            startMinute: s,
            endMinute: e > s ? e : s + 60,
          ),
        );
  }

  Future<void> _pickCalendar(
    BuildContext context,
    WidgetRef ref,
    List<Member> calendars,
    String? current,
  ) async {
    final href = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Lern-Kalender wählen'),
        children: [
          for (final m in calendars)
            ListTile(
              leading: CircleAvatar(backgroundColor: m.color, radius: 8),
              title: Text(m.name),
              trailing: m.href == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, m.href),
            ),
        ],
      ),
    );
    if (href != null) {
      await ref.read(studyCalendarHrefProvider.notifier).set(href);
    }
  }

  Future<void> _share(BuildContext context, WidgetRef ref, String href) async {
    final cols = await ref.read(collectionsProvider.future);
    if (!context.mounted) return;
    for (final c in cols) {
      if (c.href == href) {
        await showShareSheet(context, c);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lern-Kalender nicht gefunden.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows =
        ref.watch(studyWindowsProvider).value ?? defaultStudyWindows();
    final calHref = ref.watch(studyCalendarHrefProvider).value;
    final calendars = ref
        .watch(membersProvider)
        .where((m) => m.supportsEvents)
        .toList();
    String calName = 'Noch keiner gewählt';
    for (final m in calendars) {
      if (m.href == calHref) calName = m.name;
    }
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Lernen')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'LERN-KALENDER',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_shared_outlined),
            title: const Text('Lern-Kalender'),
            subtitle: Text(
              calHref == null
                  ? 'Hier landen die Lern-Termine – bitte wählen'
                  : calName,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickCalendar(context, ref, calendars, calHref),
          ),
          if (calHref != null)
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Mit Eltern teilen'),
              subtitle: const Text(
                'Diesen Kalender für die Eltern freigeben, damit sie die '
                'Lern-Termine sehen.',
              ),
              onTap: () => _share(context, ref, calHref),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'LERNZEITEN',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Text(
              'Wann darf gelernt werden? Lern-Einheiten werden nur in diese '
              'Zeitfenster gelegt.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (var i = 0; i < 7; i++)
            SwitchListTile(
              value: windows[i].enabled,
              title: Text(_dayNames[i]),
              subtitle: Text(
                windows[i].enabled
                    ? '${_fmt(windows[i].startMinute)}–${_fmt(windows[i].endMinute)}'
                    : 'Kein Lernen',
              ),
              secondary: windows[i].enabled
                  ? IconButton(
                      tooltip: 'Zeit ändern',
                      icon: const Icon(Icons.schedule),
                      onPressed: () => _editTime(context, ref, i, windows[i]),
                    )
                  : null,
              onChanged: (v) => ref
                  .read(studyWindowsProvider.notifier)
                  .setDay(i, windows[i].copyWith(enabled: v)),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
