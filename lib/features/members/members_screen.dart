import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/utils/hex_color.dart';
import 'member_settings.dart';

/// Farbpalette für Mitglieder (als Hex, damit keine Color→Hex-Konvertierung
/// nötig ist).
const _palette = [
  '#EF5350', '#42A5F5', '#66BB6A', '#FFA726',
  '#AB47BC', '#26C6DA', '#EC407A', '#8D6E63',
  '#5C6BC0', '#26A69A', '#FF7043', '#9CCC65',
];

/// Verwaltung der Familienmitglieder: jeder Kalender bekommt Name, Farbe und
/// kann ein-/ausgeblendet werden (lokal auf diesem Gerät).
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Mitglieder & Farben')),
      body: members.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Keine Kalender gefunden. Verbinde zuerst deine Nextcloud '
                  'im Tab „Familie".',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Gib jedem Kalender einen Namen und eine Farbe (z. B. pro '
                    'Person). Ausgeblendete Kalender erscheinen nicht im '
                    'Kalender und Dashboard. Gilt nur auf diesem Gerät.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                for (final m in members)
                  _MemberTile(member: m),
              ],
            ),
    );
  }
}

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});
  final Member member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(memberSettingsProvider.notifier);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: InkWell(
          onTap: () => _pickColor(context, ref),
          borderRadius: BorderRadius.circular(20),
          child: CircleAvatar(
            backgroundColor: member.color,
            child: const Icon(Icons.edit, size: 16, color: Colors.white),
          ),
        ),
        title: Text(member.name),
        subtitle: Text(member.hidden ? 'Ausgeblendet' : 'Sichtbar'),
        trailing: Switch(
          value: !member.hidden,
          onChanged: (visible) => notifier.setHidden(member.href, !visible),
        ),
        onTap: () => _rename(context, ref),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: member.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name ändern'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name (z. B. Anna)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Speichern')),
        ],
      ),
    );
    if (name != null) {
      await ref.read(memberSettingsProvider.notifier).setName(member.href, name);
    }
  }

  Future<void> _pickColor(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Farbe für „${member.name}"',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final hex in _palette)
                    InkWell(
                      onTap: () {
                        ref
                            .read(memberSettingsProvider.notifier)
                            .setColorHex(member.href, hex);
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: CircleAvatar(
                        radius: 22,
                        backgroundColor: parseHexColor(hex),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  ref
                      .read(memberSettingsProvider.notifier)
                      .setColorHex(member.href, null);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.restart_alt),
                label: const Text('Standard (Kalenderfarbe)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
