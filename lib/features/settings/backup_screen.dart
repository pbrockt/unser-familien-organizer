import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_providers.dart';
import '../../core/backup/backup_service.dart';
import 'backup_providers.dart';

/// Sicherung & Wiederherstellung der App-Einstellungen und Vorlagen auf der
/// Nextcloud (CalDAV-Daten liegen ohnehin auf dem Server).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;
  Future<List<BackupFile>>? _listFuture;

  BackupService? _service() {
    final account = ref.read(accountProvider).value;
    return account == null ? null : BackupService(account);
  }

  void _reloadList() {
    final svc = _service();
    setState(() => _listFuture = svc?.listBackups() ?? Future.value([]));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadList());
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _backupNow() async {
    final svc = _service();
    if (svc == null) return;
    setState(() => _busy = true);
    try {
      await svc.createBackup();
      await svc.pruneOld();
      await ref.read(backupLastProvider.notifier).markNow();
      _snack('Sicherung auf der Nextcloud erstellt.');
      _reloadList();
    } catch (e) {
      _snack('Sichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(BackupFile file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wiederherstellen?'),
        content: Text(
          'Die Einstellungen & Vorlagen werden aus „${file.name}" '
          'überschrieben. Termine/Aufgaben bleiben unverändert.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Wiederherstellen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final svc = _service();
    if (svc == null) return;
    setState(() => _busy = true);
    try {
      final data = await svc.download(file);
      await BackupService.applyBackupMap(data);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Wiederhergestellt ✅'),
          content: const Text(
            'Bitte starte die App neu, damit alle Einstellungen übernommen '
            'werden.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _snack('Wiederherstellen fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(BackupFile file) async {
    final svc = _service();
    if (svc == null) return;
    try {
      await svc.delete(file);
      _reloadList();
    } catch (e) {
      _snack('Löschen fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider).value;
    final freq = ref.watch(backupFrequencyProvider).value ?? 'weekly';
    final last = ref.watch(backupLastProvider).value;

    if (account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sicherung')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Verbinde zuerst deine Nextcloud (Einstellungen → Familie), '
              'um Sicherungen anzulegen.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Sicherung & Wiederherstellung')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Einstellungen & Vorlagen werden als Datei in deiner Nextcloud '
              '(Ordner „FamilyPlanner/Backups") gesichert. Termine und Aufgaben '
              'liegen ohnehin auf dem Server.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Jetzt sichern'),
            subtitle: Text(
              last == null
                  ? 'Noch keine Sicherung'
                  : 'Zuletzt: ${DateFormat('d. MMM y, HH:mm', 'de_DE').format(last)}',
            ),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _backupNow,
          ),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Automatisch sichern'),
            trailing: DropdownButton<String>(
              value: freq,
              onChanged: (v) {
                if (v != null) {
                  ref.read(backupFrequencyProvider.notifier).set(v);
                }
              },
              items: const [
                DropdownMenuItem(value: 'none', child: Text('Aus')),
                DropdownMenuItem(value: 'daily', child: Text('Täglich')),
                DropdownMenuItem(value: 'weekly', child: Text('Wöchentlich')),
                DropdownMenuItem(value: 'monthly', child: Text('Monatlich')),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Vorhandene Sicherungen',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FutureBuilder<List<BackupFile>>(
            future: _listFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Fehler beim Laden: ${snap.error}'),
                );
              }
              final files = snap.data ?? const [];
              if (files.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Noch keine Sicherungen vorhanden.'),
                );
              }
              return Column(
                children: [
                  for (final f in files)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(f.name),
                      subtitle: f.modified == null
                          ? null
                          : Text(
                              DateFormat(
                                'd. MMM y, HH:mm',
                                'de_DE',
                              ).format(f.modified!.toLocal()),
                            ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Wiederherstellen',
                            icon: const Icon(Icons.restore),
                            onPressed: _busy ? null : () => _restore(f),
                          ),
                          IconButton(
                            tooltip: 'Löschen',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy ? null : () => _delete(f),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
