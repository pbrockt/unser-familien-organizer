import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/background/background_sync.dart';
import '../../core/platform/platform_support.dart';
import '../calendar/birthdays.dart';
import '../../shared/theme/app_theme.dart';
import '../calendar/event_providers.dart';
import '../calendar/event_templates.dart';
import '../family/family_screen.dart';
import '../home/dashboard_providers.dart';
import '../members/member_settings.dart';
import '../study/study_settings_screen.dart';
import '../tasks/task_providers.dart';
import '../weather/weather_service.dart';
import 'about_update_sheet.dart';
import 'backup_screen.dart';
import 'briefing_planner.dart';
import 'briefing_providers.dart';
import 'notification_providers.dart';
import 'permissions_screen.dart';
import 'theme_provider.dart';

/// Einstellungen: nach Kategorien gegliedert (aufklappbare Bereiche), damit
/// der Überblick erhalten bleibt.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _versionTaps = 0;

  Future<void> _toggleEnabled(bool value) async {
    final service = ref.read(notificationServiceProvider);
    if (value) {
      final granted = await service.requestPermission();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Berechtigung nicht erteilt. Erinnerungen brauchen '
                'die Benachrichtigungs-Berechtigung.',
              ),
            ),
          );
        }
        return;
      }
    }
    await ref.read(notificationSettingsProvider.notifier).setEnabled(value);
    // Der periodische Hintergrund-Sync läuft unabhängig weiter (für die
    // Home-Widgets). Beim Deaktivieren nur die geplanten Erinnerungen löschen –
    // der Task plant ohnehin nur Erinnerungen, wenn aktiviert.
    if (value) {
      await registerBackgroundSync();
    } else {
      await service.cancelAll();
    }
  }

  /// Sendet sofort ein Test-Briefing (zur Prüfung von Inhalt & Benachrichtigung).
  Future<void> _sendBriefingTest() async {
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(notificationServiceProvider);
    if (!await service.areNotificationsEnabled()) {
      final granted = await service.requestPermission();
      if (!granted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Benachrichtigungen sind nicht erlaubt.'),
          ),
        );
        return;
      }
    }
    final now = DateTime.now();
    final body = briefingBody(
      events: ref.read(visibleEventsProvider),
      taskLists: ref.read(tasksControllerProvider).value ?? const [],
      weather: ref.read(weatherProvider).value ?? const {},
      day: DateTime(now.year, now.month, now.day),
    );
    await service.showNow(title: '☀️ Tages-Briefing (Test)', body: body);
    messenger.showSnackBar(
      const SnackBar(content: Text('Test-Briefing gesendet.')),
    );
  }

  /// Easter Egg: 5× auf die Versionsnummer tippen zeigt eine Danksagung.
  void _onVersionTap() {
    _versionTaps++;
    if (_versionTaps < 5) return;
    _versionTaps = 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Danke, dass du dabei bist! 💛'),
        content: const Text(
          'Diese App ist mit viel Liebe für unsere Familie entstanden – '
          'gemeinsam von Phillipp und Claude. 🛠️\n\n'
          'Schön, dass du „Unser Familien-Organizer" nutzt. '
          'Wir sind einfach happy! 🎉',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('🥳 Weiter geht\'s'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(notificationSettingsProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final calendars = ref
        .watch(membersProvider)
        .where((m) => m.supportsEvents)
        .toList();
    final accent = ref.watch(accentColorProvider).value ?? AppTheme.orange;
    final templatesEnabled = ref.watch(templatesEnabledProvider).value ?? true;
    final weatherPlz = ref.watch(weatherPlzProvider).value ?? '';
    final upcomingDays = ref.watch(upcomingDaysProvider).value ?? 2;
    final birthdayCfg =
        ref.watch(birthdayConfigProvider).value ?? const BirthdayConfig();
    final briefing =
        ref.watch(briefingSettingsProvider).value ?? const BriefingSettings();
    const dayChoices = [1, 2, 3, 5, 7, 14];
    final daysValue = dayChoices.contains(upcomingDays) ? upcomingDays : 2;

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ExpansionPanelList.radio(
              initialOpenPanelValue: 'familie',
              elevation: 1,
              expandedHeaderPadding: EdgeInsets.zero,
              children: [
                // ---- Familie & Verbindung ----
                _panel(
                  value: 'familie',
                  icon: Icons.people_outline,
                  title: 'Familie & Verbindung',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text('Familie & Verbindung'),
                      subtitle: const Text(
                        'Nextcloud, Kalender, Mitglieder & Freigaben',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const FamilyScreen()),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.school_outlined),
                      title: const Text('Lernen'),
                      subtitle: const Text(
                        'Lernzeiten & Lern-Kalender für Schularbeiten',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const StudySettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),

                // ---- Darstellung ----
                _panel(
                  value: 'darstellung',
                  icon: Icons.palette_outlined,
                  title: 'Darstellung',
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode),
                            label: Text('Hell'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode),
                            label: Text('Dunkel'),
                          ),
                        ],
                        selected: {themeMode},
                        onSelectionChanged: (s) =>
                            ref.read(themeModeProvider.notifier).set(s.first),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        'Akzentfarbe',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
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
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSurface
                                        : Colors.transparent,
                                    width: 3,
                                  ),
                                ),
                                child: c.toARGB32() == accent.toARGB32()
                                    ? const Icon(
                                        Icons.check,
                                        size: 18,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.dark_mode_outlined),
                      title: const Text('AMOLED-Schwarz'),
                      subtitle: const Text(
                        'Reines Schwarz im Dunkelmodus – spart Akku auf '
                        'OLED-Displays',
                      ),
                      value: ref.watch(amoledProvider).value ?? false,
                      onChanged: (v) =>
                          ref.read(amoledProvider.notifier).set(v),
                    ),
                  ],
                ),

                // ---- Benachrichtigungen & Briefing ----
                if (isAndroid)
                  _panel(
                    value: 'benachrichtigungen',
                    icon: Icons.notifications_active_outlined,
                    title: 'Benachrichtigungen & Briefing',
                    children: [
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: const Text('Erinnerungen aktivieren'),
                        subtitle: const Text(
                          'Benachrichtigung vor Terminen und bei fälligen Aufgaben',
                        ),
                        value: settings.enabled,
                        onChanged: _toggleEnabled,
                      ),
                      if (settings.enabled)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            'Die Vorlaufzeit (5 Min … 1 Std) stellst du pro Termin '
                            'im Termin-Editor ein – standardmäßig ist sie aus.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      SwitchListTile(
                        secondary: const Icon(Icons.wb_twilight),
                        title: const Text('Tages-Briefing (morgens)'),
                        subtitle: const Text(
                          'Tägliche Übersicht: Termine, fällige Aufgaben & Wetter',
                        ),
                        value: briefing.enabled,
                        onChanged: (v) => ref
                            .read(briefingSettingsProvider.notifier)
                            .setEnabled(v),
                      ),
                      if (briefing.enabled)
                        ListTile(
                          leading: const Icon(Icons.schedule),
                          title: const Text('Uhrzeit des Briefings'),
                          trailing: Text(
                            '${briefing.hour.toString().padLeft(2, '0')}:'
                            '${briefing.minute.toString().padLeft(2, '0')} Uhr',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(
                                hour: briefing.hour,
                                minute: briefing.minute,
                              ),
                            );
                            if (picked != null) {
                              await ref
                                  .read(briefingSettingsProvider.notifier)
                                  .setTime(picked.hour * 60 + picked.minute);
                            }
                          },
                        ),
                      ListTile(
                        leading: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: const Text('Test-Briefing jetzt senden'),
                        subtitle: const Text(
                          'Zeigt sofort die heutige Übersicht als Benachrichtigung',
                        ),
                        onTap: _sendBriefingTest,
                      ),
                      ListTile(
                        leading: const Icon(Icons.shield_outlined),
                        title: const Text('Berechtigungen'),
                        subtitle: const Text(
                          'Benachrichtigungen, Hintergrund-Aktualisierung & Mikrofon',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PermissionsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),

                // ---- Kalender & Startseite ----
                _panel(
                  value: 'kalender',
                  icon: Icons.calendar_month_outlined,
                  title: 'Kalender & Startseite',
                  children: [
                    if (calendars.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          'Welche Kalender unter „Anstehende Termine" erscheinen, '
                          'stellst du direkt auf der Startseite über den Filter ein.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.hourglass_bottom),
                            label: const Text('Countdown'),
                            onPressed: _pickCountdownCalendars,
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.date_range_outlined),
                        title: const Text('Anstehende Termine: Vorschau'),
                        subtitle: const Text(
                          'Wie viele Tage im Voraus auf der Startseite?',
                        ),
                        trailing: DropdownButton<int>(
                          value: daysValue,
                          items: const [
                            DropdownMenuItem(
                              value: 1,
                              child: Text('Nur heute'),
                            ),
                            DropdownMenuItem(
                              value: 2,
                              child: Text('Heute + morgen'),
                            ),
                            DropdownMenuItem(value: 3, child: Text('3 Tage')),
                            DropdownMenuItem(value: 5, child: Text('5 Tage')),
                            DropdownMenuItem(value: 7, child: Text('1 Woche')),
                            DropdownMenuItem(
                              value: 14,
                              child: Text('2 Wochen'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              ref.read(upcomingDaysProvider.notifier).set(v);
                            }
                          },
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.cake_outlined),
                        title: const Text('Geburtstags-Kalender'),
                        subtitle: Text(
                          birthdayCfg.calendarHref == null
                              ? 'Keiner gewählt'
                              : calendars
                                    .firstWhere(
                                      (m) => m.href == birthdayCfg.calendarHref,
                                      orElse: () => calendars.first,
                                    )
                                    .name,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            _pickBirthdayCalendar(calendars, birthdayCfg),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.contacts_outlined),
                        title: const Text(
                          'Geburtstage auch aus anderen Quellen',
                        ),
                        subtitle: const Text(
                          'Geburtstage zusätzlich am Namen erkennen (z. B. '
                          'Kontakte-Geburtstage oder Einträge mit „Geburtstag")',
                        ),
                        value: birthdayCfg.useHeuristic,
                        onChanged: (v) => ref
                            .read(birthdayConfigProvider.notifier)
                            .setUseHeuristic(v),
                      ),
                    ],
                    SwitchListTile(
                      secondary: const Icon(Icons.bookmark_outline),
                      title: const Text('Termin-Vorlagen'),
                      subtitle: const Text(
                        'Beim Tippen Vorschläge zeigen und Termine als Vorlage '
                        'speichern können',
                      ),
                      value: templatesEnabled,
                      onChanged: (v) =>
                          ref.read(templatesEnabledProvider.notifier).set(v),
                    ),
                    ListTile(
                      leading: const Icon(Icons.wb_sunny_outlined),
                      title: const Text('Wetter im Kalender'),
                      subtitle: Text(
                        weatherPlz.isEmpty
                            ? 'Aus – Postleitzahl eingeben zum Aktivieren'
                            : 'PLZ $weatherPlz',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _editPlz(weatherPlz),
                    ),
                  ],
                ),

                // ---- Sicherung & Updates ----
                _panel(
                  value: 'sicherung',
                  icon: Icons.cloud_sync_outlined,
                  title: 'Sicherung & Updates',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.system_update),
                      title: const Text('Nach Updates suchen'),
                      subtitle: const Text('Neueste Version von GitHub laden'),
                      onTap: () => showAboutUpdateSheet(context),
                    ),
                    ListTile(
                      leading: const Icon(Icons.cloud_sync_outlined),
                      title: const Text('Sicherung & Wiederherstellung'),
                      subtitle: const Text(
                        'Einstellungen & Vorlagen auf der Nextcloud sichern',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const BackupScreen()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Version direkt anzeigen (keine eigene Kategorie „Über").
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                return ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Version'),
                  subtitle: Text(
                    info == null
                        ? '…'
                        : '${info.version} (${info.buildNumber})',
                  ),
                  onTap: _onVersionTap,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Auswahl des Geburtstags-Kalenders („Keiner" möglich).
  Future<void> _pickBirthdayCalendar(
    List<Member> calendars,
    BirthdayConfig cfg,
  ) async {
    final href = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Geburtstags-Kalender'),
        children: [
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Keiner'),
            trailing: cfg.calendarHref == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, '__none__'),
          ),
          for (final m in calendars)
            ListTile(
              leading: CircleAvatar(backgroundColor: m.color, radius: 8),
              title: Text(m.name),
              trailing: m.href == cfg.calendarHref
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.pop(ctx, m.href),
            ),
        ],
      ),
    );
    if (href == null) return;
    await ref
        .read(birthdayConfigProvider.notifier)
        .setCalendar(href == '__none__' ? null : href);
  }

  /// Countdown-Popup: pro Kalender an/aus + „alle Termine" oder „nur nächster".
  Future<void> _pickCountdownCalendars() async {
    final calendars = ref
        .read(membersProvider)
        .where((m) => m.supportsEvents)
        .toList();
    final cur = ref.read(memberSettingsProvider).value ?? const {};
    final enabled = {
      for (final m in calendars) m.href: cur[m.href]?.countdown ?? false,
    };
    final allMode = {
      for (final m in calendars) m.href: cur[m.href]?.countdownAll ?? false,
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
                    onChanged: (v) => setS(() => enabled[m.href] = v ?? false),
                    secondary: CircleAvatar(
                      backgroundColor: m.color,
                      radius: 8,
                    ),
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

  /// Aufklappbares Panel für die Einstellungen. Über [ExpansionPanelList.radio]
  /// ist immer nur eine Kategorie gleichzeitig geöffnet (Öffnen schließt die
  /// anderen).
  ExpansionPanelRadio _panel({
    required String value,
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return ExpansionPanelRadio(
      value: value,
      canTapOnHeader: true,
      headerBuilder: (context, isExpanded) => ListTile(
        leading: Icon(icon),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      body: Column(children: children),
    );
  }
}
