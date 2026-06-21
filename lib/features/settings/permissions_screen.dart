import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/platform/battery_optimization.dart';
import 'notification_providers.dart';

/// Eigene Seite, die alle App-Berechtigungen bündelt: Benachrichtigungen,
/// Hintergrund-Aktualisierung (Akku) und Mikrofon (Sprach-Schnelleingabe).
class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  bool? _notif;
  bool? _battery;
  bool? _mic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  Future<void> _refreshAll() async {
    await Future.wait([_refreshNotif(), _refreshBattery(), _refreshMic()]);
  }

  Future<void> _refreshNotif() async {
    final granted = await ref
        .read(notificationServiceProvider)
        .areNotificationsEnabled();
    if (mounted) setState(() => _notif = granted);
  }

  Future<void> _refreshBattery() async {
    final ignored = await BatteryOptimization.isIgnoring();
    if (mounted) setState(() => _battery = ignored);
  }

  Future<void> _refreshMic() async {
    try {
      final has = await SpeechToText().hasPermission;
      if (mounted) setState(() => _mic = has);
    } catch (_) {
      if (mounted) setState(() => _mic = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget statusTile({
      required IconData okIcon,
      required IconData badIcon,
      required bool? granted,
      required String title,
      required String okText,
      required String badText,
      required Future<void> Function() onRequest,
    }) {
      return ListTile(
        leading: Icon(
          granted == true ? okIcon : badIcon,
          color: granted == true ? Colors.green : scheme.error,
        ),
        title: Text(title),
        subtitle: Text(
          granted == null
              ? 'Status wird geprüft…'
              : granted
              ? okText
              : badText,
        ),
        trailing: granted == true
            ? null
            : TextButton(
                onPressed: () async {
                  await onRequest();
                },
                child: const Text('Erlauben'),
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Berechtigungen')),
      body: ListView(
        children: [
          statusTile(
            okIcon: Icons.check_circle,
            badIcon: Icons.error_outline,
            granted: _notif,
            title: 'Benachrichtigungen',
            okText: 'Erlaubt',
            badText: 'Nicht erlaubt – für Erinnerungen nötig',
            onRequest: () async {
              await ref.read(notificationServiceProvider).requestPermission();
              await _refreshNotif();
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Test-Benachrichtigung senden'),
            onTap: () async {
              await ref.read(notificationServiceProvider).showTest();
            },
          ),
          const Divider(),
          statusTile(
            okIcon: Icons.battery_charging_full,
            badIcon: Icons.battery_alert,
            granted: _battery,
            title: 'Hintergrund-Aktualisierung',
            okText: 'Akku-Optimierung aus – Erinnerungen kommen zuverlässig',
            badText:
                'Akku-Optimierung aktiv – Erinnerungen können verspätet '
                'kommen oder ausbleiben',
            onRequest: () async {
              await BatteryOptimization.request();
              await _refreshBattery();
            },
          ),
          const Divider(),
          statusTile(
            okIcon: Icons.mic,
            badIcon: Icons.mic_off,
            granted: _mic,
            title: 'Mikrofon',
            okText: 'Erlaubt – Sprach-Schnelleingabe nutzbar',
            badText: 'Nicht erlaubt – für die Sprach-Schnelleingabe nötig',
            onRequest: () async {
              try {
                await SpeechToText().initialize();
              } catch (_) {}
              await _refreshMic();
            },
          ),
        ],
      ),
    );
  }
}
