import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../family/share_calendar_sheet.dart';
import '../members/member_settings.dart';
import '../members/user_groups.dart';
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
          header('ELTERN-RECHTE'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              'Eltern dürfen Arbeiten bearbeiten und alle Lern-Tage abhaken. '
              'Kinder können nur ihre eigenen (zugewiesenen) Lern-Tage abhaken. '
              'Eltern-Rechte gelten automatisch, wenn du in der Eltern-Gruppe '
              'bist – oder über den Geräte-Schalter unten.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Builder(
            builder: (context) {
              final groups =
                  ref.watch(userGroupsProvider).value ?? const <String>[];
              final selected = ref.watch(parentGroupProvider).value;
              final isParent = ref.watch(effectiveParentModeProvider);
              return Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.groups_outlined),
                    title: const Text('Nextcloud-Gruppen'),
                    subtitle: Text(
                      groups.isEmpty
                          ? 'Noch keine geladen – bitte synchronisieren '
                                '(Avatar antippen)'
                          : groups.join(', '),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      isParent
                          ? Icons.verified_user_outlined
                          : Icons.supervisor_account_outlined,
                      color: isParent ? scheme.primary : null,
                    ),
                    title: const Text('Eltern-Gruppe'),
                    subtitle: Text(
                      isParent
                          ? 'Du hast Eltern-Rechte ✓'
                          : 'Keine Eltern-Rechte über eine Gruppe',
                    ),
                    trailing: DropdownButton<String>(
                      value: (selected != null && groups.contains(selected))
                          ? selected
                          : '__auto__',
                      items: [
                        const DropdownMenuItem(
                          value: '__auto__',
                          child: Text('Automatisch'),
                        ),
                        for (final g in groups)
                          DropdownMenuItem(value: g, child: Text(g)),
                      ],
                      onChanged: (v) => ref
                          .read(parentGroupProvider.notifier)
                          .set(v == '__auto__' ? null : v),
                    ),
                  ),
                ],
              );
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.smartphone_outlined),
            title: const Text('Eltern-Gerät (dieses Gerät)'),
            subtitle: const Text(
              'Override: gewährt diesem Gerät Eltern-Rechte, auch ohne Gruppe.',
            ),
            value: ref.watch(parentModeProvider).value ?? false,
            onChanged: (v) => ref.read(parentModeProvider.notifier).set(v),
          ),
          const Divider(),
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
          header('PERSONEN'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              'Schüler:innen, für die Arbeiten angelegt werden. Neue Personen '
              'legst du direkt beim Erstellen einer Schularbeit an.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final p in ref.watch(studyPersonsProvider).value ?? const [])
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(p),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Entfernen',
                onPressed: () =>
                    ref.read(studyPersonsProvider.notifier).remove(p),
              ),
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
