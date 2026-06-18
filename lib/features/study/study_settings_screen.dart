import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../family/share_calendar_sheet.dart';
import '../members/member_settings.dart';
import 'study_settings.dart';
import 'study_windows_editor.dart';

/// Einstellungen rund ums Lernen: erlaubte Lernzeiten je Wochentag und der
/// (Standard-)Kalender, in den die generierten Lern-Termine geschrieben werden.
class StudySettingsScreen extends ConsumerWidget {
  const StudySettingsScreen({super.key});

  Future<void> _pickCalendar(
    BuildContext context,
    WidgetRef ref,
    List<Member> calendars,
    String? current,
  ) async {
    final href = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Standard-Lern-Kalender'),
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
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        t,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Lernen')),
      body: ListView(
        children: [
          header('STANDARD-LERN-KALENDER'),
          ListTile(
            leading: const Icon(Icons.folder_shared_outlined),
            title: const Text('Standard-Lern-Kalender'),
            subtitle: Text(
              calHref == null
                  ? 'Optional – beim Anlegen einer Schularbeit wählbar'
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
          header('LERNZEITEN'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              'Wann darf gelernt werden? Schalter = Tag an/aus, Zeile antippen = '
              'Uhrzeiten ändern. Lern-Einheiten werden nur in diese Fenster gelegt.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const StudyWindowsEditor(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
