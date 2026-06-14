import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../core/caldav/caldav_client.dart';
import '../../shared/utils/hex_color.dart';
import '../../shared/widgets/countdown_confirm_dialog.dart';
import '../members/members_screen.dart';
import 'connection_screen.dart';
import 'new_calendar_sheet.dart';
import 'share_calendar_sheet.dart';

/// Familien-Bereich: Nextcloud-Verbindung verwalten und die entdeckten
/// Kalender/Listen anzeigen.
class FamilyScreen extends ConsumerWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Familie')),
      body: accountAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (account) => account == null
            ? _NotConnected(onConnect: () => _openConnection(context))
            : _Connected(
                account: account,
                onEdit: () => _openConnection(context, existing: account),
              ),
      ),
    );
  }

  void _openConnection(BuildContext context, {NextcloudAccount? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionScreen(existing: existing),
      ),
    );
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected({required this.onConnect});
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Noch nicht verbunden', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Verbinde deine eigene Nextcloud, um Kalender, Aufgaben und '
              'Einkaufslisten der Familie zu synchronisieren.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onConnect,
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Nextcloud verbinden'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Connected extends ConsumerWidget {
  const _Connected({required this.account, required this.onEdit});
  final NextcloudAccount account;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsProvider);

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(collectionsProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.cloud_done)),
              title: Text(account.username),
              subtitle: Text(account.baseUrl),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Bearbeiten',
                onPressed: onEdit,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.palette_outlined)),
              title: const Text('Mitglieder & Farben'),
              subtitle: const Text('Namen, Farben & Sichtbarkeit pro Kalender'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MembersScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Kalender & Listen',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton.icon(
                onPressed: () => _createCollection(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Neu'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          collectionsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('$e'),
              ),
            ),
            data: (collections) => collections.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Keine Kalender/Listen gefunden.'),
                  )
                : Column(
                    children: collections
                        .map((c) => _CollectionTile(collection: c))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _confirmDisconnect(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Verbindung trennen'),
          ),
        ],
      ),
    );
  }

  Future<void> _createCollection(BuildContext context, WidgetRef ref) async {
    final created = await showNewCalendarSheet(context);
    if (created == true) {
      ref.invalidate(collectionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Angelegt ✓')),
        );
      }
    }
  }

  Future<void> _confirmDisconnect(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verbindung trennen?'),
        content: const Text(
            'Die gespeicherten Zugangsdaten werden vom Gerät gelöscht. '
            'Deine Daten in der Nextcloud bleiben erhalten.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Trennen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(accountProvider.notifier).disconnect();
    }
  }
}

class _CollectionTile extends ConsumerWidget {
  const _CollectionTile({required this.collection});
  final CalDavCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = <String>[
      if (collection.supportsEvents) 'Termine',
      if (collection.supportsTodos) 'Aufgaben',
    ];
    final color = parseHexColor(collection.color);
    return Card(
      child: GestureDetector(
        onLongPressStart: (d) => _showMenu(context, ref, d.globalPosition),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: color ?? Theme.of(context).colorScheme.primary,
            radius: 12,
          ),
          title: Text(collection.displayName),
          subtitle: Text(types.isEmpty ? 'Collection' : types.join(' · ')),
          trailing: IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Freigeben',
            onPressed: () => showShareSheet(context, collection),
          ),
        ),
      ),
    );
  }

  Future<void> _showMenu(
      BuildContext context, WidgetRef ref, Offset position) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Umbenennen'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Löschen'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
    if (!context.mounted) return;
    if (selected == 'rename') {
      await _rename(context, ref);
    } else if (selected == 'delete') {
      await _delete(context, ref);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: collection.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Umbenennen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
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
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == collection.displayName) {
      return;
    }
    final account = ref.read(accountProvider).value;
    if (account == null) return;
    try {
      await ref
          .read(caldavClientProvider)
          .renameCalendar(account, collection.href, newName);
      ref.invalidate(collectionsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Umbenennen fehlgeschlagen: $e')));
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showCountdownDeleteDialog(
      context,
      title: '„${collection.displayName}" löschen?',
      message: 'Der Kalender/die Liste wird mit allen Einträgen aus der '
          'Nextcloud gelöscht. Das kann nicht rückgängig gemacht werden.',
      seconds: 5,
    );
    if (!ok) return;
    final account = ref.read(accountProvider).value;
    if (account == null) return;
    try {
      await ref
          .read(caldavClientProvider)
          .deleteCalendar(account, collection.href);
      ref.invalidate(collectionsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: $e')));
      }
    }
  }
}
