import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'about_update_sheet.dart';
import 'notification_providers.dart';

/// Einstellungen: Benachrichtigungen & Berechtigungen, App-Update.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool? _permissionGranted;

  @override
  void initState() {
    super.initState();
    _refreshPermission();
  }

  Future<void> _refreshPermission() async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.areNotificationsEnabled();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  Future<void> _toggleEnabled(bool value) async {
    final service = ref.read(notificationServiceProvider);
    if (value) {
      final granted = await service.requestPermission();
      await _refreshPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Berechtigung nicht erteilt. Erinnerungen brauchen '
                  'die Benachrichtigungs-Berechtigung.'),
            ),
          );
        }
        return;
      }
    }
    await ref.read(notificationSettingsProvider.notifier).setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          children: [
            _sectionHeader(context, 'Erinnerungen'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Erinnerungen aktivieren'),
              subtitle: const Text(
                  'Lokale Benachrichtigung vor anstehenden Terminen'),
              value: settings.enabled,
              onChanged: _toggleEnabled,
            ),
            if (settings.enabled)
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Vorlaufzeit'),
                subtitle: const Text('Wie früh vor Beginn erinnern?'),
                trailing: DropdownButton<int>(
                  value: settings.leadMinutes,
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('10 Min')),
                    DropdownMenuItem(value: 15, child: Text('15 Min')),
                    DropdownMenuItem(value: 30, child: Text('30 Min')),
                    DropdownMenuItem(value: 60, child: Text('1 Std')),
                    DropdownMenuItem(value: 120, child: Text('2 Std')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(notificationSettingsProvider.notifier)
                          .setLeadMinutes(v);
                    }
                  },
                ),
              ),
            const Divider(),
            _sectionHeader(context, 'Berechtigungen'),
            ListTile(
              leading: Icon(
                _permissionGranted == true
                    ? Icons.check_circle
                    : Icons.error_outline,
                color: _permissionGranted == true
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
              title: const Text('Benachrichtigungen'),
              subtitle: Text(_permissionGranted == null
                  ? 'Status wird geprüft…'
                  : _permissionGranted!
                      ? 'Erlaubt'
                      : 'Nicht erlaubt – für Erinnerungen nötig'),
              trailing: _permissionGranted == true
                  ? null
                  : TextButton(
                      onPressed: () async {
                        await ref
                            .read(notificationServiceProvider)
                            .requestPermission();
                        await _refreshPermission();
                      },
                      child: const Text('Erlauben'),
                    ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('Test-Benachrichtigung senden'),
              onTap: () async {
                await ref.read(notificationServiceProvider).showTest();
              },
            ),
            const Divider(),
            _sectionHeader(context, 'App'),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Nach Updates suchen'),
              subtitle: const Text('Neueste Version von GitHub laden'),
              onTap: () => showAboutUpdateSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}
