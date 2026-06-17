import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/background/background_sync.dart';
import '../../core/platform/battery_optimization.dart';
import '../../core/platform/platform_support.dart';
import '../../shared/theme/app_theme.dart';
import '../calendar/event_templates.dart';
import '../family/family_screen.dart';
import '../members/member_settings.dart';
import '../weather/weather_service.dart';
import 'about_update_sheet.dart';
import 'notification_providers.dart';
import 'theme_provider.dart';

/// Einstellungen: Benachrichtigungen & Berechtigungen, App-Update.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool? _permissionGranted;
  bool? _batteryIgnored;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
    _refreshBattery();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nach Rückkehr aus den System-Dialogen (Akku/Benachrichtigungen) Status neu
    // prüfen.
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
      _refreshBattery();
    }
  }

  Future<void> _refreshPermission() async {
    final service = ref.read(notificationServiceProvider);
    final granted = await service.areNotificationsEnabled();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  Future<void> _refreshBattery() async {
    final ignored = await BatteryOptimization.isIgnoring();
    if (mounted) setState(() => _batteryIgnored = ignored);
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
    // Hintergrund-Sync entsprechend starten/stoppen.
    if (value) {
      await registerBackgroundSync();
    } else {
      await cancelBackgroundSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(notificationSettingsProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final calendars =
        ref.watch(membersProvider).where((m) => m.supportsEvents).toList();
    final calSettings = ref.watch(memberSettingsProvider).value ?? const {};
    final accent = ref.watch(accentColorProvider).value ?? AppTheme.orange;
    final templatesEnabled = ref.watch(templatesEnabledProvider).value ?? true;
    final weatherPlz = ref.watch(weatherPlzProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          children: [
            _sectionHeader(context, 'Konto'),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Familie & Verbindung'),
              subtitle:
                  const Text('Nextcloud, Kalender, Mitglieder & Freigaben'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FamilyScreen()),
              ),
            ),
            const Divider(),
            _sectionHeader(context, 'Darstellung'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto),
                      label: Text('System')),
                  ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode),
                      label: Text('Hell')),
                  ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode),
                      label: Text('Dunkel')),
                ],
                selected: {themeMode},
                onSelectionChanged: (s) =>
                    ref.read(themeModeProvider.notifier).set(s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('Akzentfarbe',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in AppTheme.accentChoices)
                    GestureDetector(
                      onTap: () =>
                          ref.read(accentColorProvider.notifier).set(c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.toARGB32() == accent.toARGB32()
                                ? Theme.of(context).colorScheme.onSurface
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: c.toARGB32() == accent.toARGB32()
                            ? const Icon(Icons.check,
                                size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            if (isAndroid) ...[
            _sectionHeader(context, 'Erinnerungen'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Erinnerungen aktivieren'),
              subtitle: const Text(
                  'Benachrichtigung vor Terminen und bei fälligen Aufgaben'),
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
            ListTile(
              leading: Icon(
                _batteryIgnored == true
                    ? Icons.battery_charging_full
                    : Icons.battery_alert,
                color: _batteryIgnored == true
                    ? Colors.green
                    : Theme.of(context).colorScheme.error,
              ),
              title: const Text('Hintergrund-Aktualisierung'),
              subtitle: Text(_batteryIgnored == null
                  ? 'Status wird geprüft…'
                  : _batteryIgnored!
                      ? 'Akku-Optimierung aus – Erinnerungen kommen zuverlässig'
                      : 'Akku-Optimierung aktiv – Erinnerungen können verspätet '
                          'kommen oder ausbleiben'),
              trailing: _batteryIgnored == true
                  ? null
                  : TextButton(
                      onPressed: () async {
                        await BatteryOptimization.request();
                        await _refreshBattery();
                      },
                      child: const Text('Erlauben'),
                    ),
            ),
            const Divider(),
            ],
            if (calendars.isNotEmpty) ...[
              _sectionHeader(context, 'Startseite'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Wähle, welche Kalender auf der Startseite erscheinen.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event_note_outlined),
                        label: const Text('Anstehende Termine'),
                        onPressed: () => _pickCalendars(
                          title: 'Anstehende Termine',
                          initial: (h) =>
                              calSettings[h]?.showOnHome ?? true,
                          apply: (h, v) => ref
                              .read(memberSettingsProvider.notifier)
                              .setShowOnHome(h, v),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.hourglass_bottom),
                        label: const Text('Countdown'),
                        onPressed: _pickCountdownCalendars,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
            ],
            _sectionHeader(context, 'Vorlagen'),
            SwitchListTile(
              secondary: const Icon(Icons.bookmark_outline),
              title: const Text('Termin-Vorlagen'),
              subtitle: const Text(
                  'Beim Tippen Vorschläge zeigen und Termine als Vorlage '
                  'speichern können'),
              value: templatesEnabled,
              onChanged: (v) =>
                  ref.read(templatesEnabledProvider.notifier).set(v),
            ),
            const Divider(),
            _sectionHeader(context, 'Wetter'),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Wetter im Kalender'),
              subtitle: Text(weatherPlz.isEmpty
                  ? 'Aus – Postleitzahl eingeben zum Aktivieren'
                  : 'PLZ $weatherPlz'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editPlz(weatherPlz),
            ),
            const Divider(),
            _sectionHeader(context, 'App'),
            ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Nach Updates suchen'),
              subtitle: const Text('Neueste Version von GitHub laden'),
              onTap: () => showAboutUpdateSheet(context),
            ),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                return ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Version'),
                  subtitle: Text(info == null
                      ? '…'
                      : '${info.version} (${info.buildNumber})'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Mehrfachauswahl-Popup: welche Kalender ein Flag bekommen.
  Future<void> _pickCalendars({
    required String title,
    required bool Function(String href) initial,
    required Future<void> Function(String href, bool value) apply,
  }) async {
    final calendars =
        ref.read(membersProvider).where((m) => m.supportsEvents).toList();
    final selected = {for (final m in calendars) m.href: initial(m.href)};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final m in calendars)
                  CheckboxListTile(
                    value: selected[m.href] ?? false,
                    onChanged: (v) =>
                        setS(() => selected[m.href] = v ?? false),
                    secondary:
                        CircleAvatar(backgroundColor: m.color, radius: 8),
                    title: Text(m.name),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      for (final m in calendars) {
        await apply(m.href, selected[m.href] ?? false);
      }
    }
  }

  /// Countdown-Popup: pro Kalender an/aus + „alle Termine" oder „nur nächster".
  Future<void> _pickCountdownCalendars() async {
    final calendars =
        ref.read(membersProvider).where((m) => m.supportsEvents).toList();
    final cur = ref.read(memberSettingsProvider).value ?? const {};
    final enabled = {
      for (final m in calendars) m.href: cur[m.href]?.countdown ?? false
    };
    final allMode = {
      for (final m in calendars) m.href: cur[m.href]?.countdownAll ?? false
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Countdown'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final m in calendars) ...[
                  CheckboxListTile(
                    value: enabled[m.href] ?? false,
                    onChanged: (v) =>
                        setS(() => enabled[m.href] = v ?? false),
                    secondary:
                        CircleAvatar(backgroundColor: m.color, radius: 8),
                    title: Text(m.name),
                  ),
                  if (enabled[m.href] ?? false)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 8),
                      child: SwitchListTile(
                        dense: true,
                        title: const Text('Alle Termine anzeigen'),
                        subtitle: const Text('Aus = nur der nächste'),
                        value: allMode[m.href] ?? false,
                        onChanged: (v) => setS(() => allMode[m.href] = v),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final notifier = ref.read(memberSettingsProvider.notifier);
      for (final m in calendars) {
        await notifier.setCountdown(m.href, enabled[m.href] ?? false);
        await notifier.setCountdownAll(m.href, allMode[m.href] ?? false);
      }
    }
  }

  /// Dialog zum Eingeben/Löschen der Wetter-PLZ.
  Future<void> _editPlz(String current) async {
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wetter-Postleitzahl'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'PLZ (Deutschland)',
            hintText: 'z.B. 26835',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('Wetter aus'),
          ),
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
    if (result != null) {
      await ref.read(weatherPlzProvider.notifier).set(result);
    }
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
