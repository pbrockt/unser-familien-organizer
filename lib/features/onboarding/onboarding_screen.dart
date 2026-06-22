import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/account_providers.dart';
import '../../core/platform/battery_optimization.dart';
import '../../core/platform/platform_support.dart';
import '../calendar/birthdays.dart';
import '../family/connection_screen.dart';
import '../settings/backup_providers.dart';
import '../settings/notification_providers.dart';

const _kOnboardingDoneKey = 'onboarding_done';

/// Wurde die Ersteinrichtung abgeschlossen?
final onboardingDoneProvider =
    AsyncNotifierProvider<OnboardingDoneController, bool>(
      OnboardingDoneController.new,
    );

class OnboardingDoneController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboardingDoneKey) ?? false;
  }

  Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDoneKey, true);
    state = const AsyncData(true);
  }
}

/// Zeigt die Ersteinrichtung beim ersten Start (einmalig).
Future<void> maybeShowOnboarding(BuildContext context, WidgetRef ref) async {
  final done = await ref.read(onboardingDoneProvider.future);
  if (done || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const OnboardingScreen(),
    ),
  );
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  static const _pageCount = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pageCount - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finish() async {
    await ref.read(onboardingDoneProvider.notifier).markDone();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = ref.watch(accountProvider).value != null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Einrichtung'),
        actions: [
          TextButton(onPressed: _finish, child: const Text('Überspringen')),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                _welcomePage(theme),
                _connectPage(theme, connected),
                _birthdayPage(theme, connected),
                _finishPage(theme),
              ],
            ),
          ),
          _dots(theme),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: _page == _pageCount - 1
                      ? FilledButton.icon(
                          onPressed: _finish,
                          icon: const Icon(Icons.check),
                          label: const Text('Fertig'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        )
                      : FilledButton(
                          onPressed: _next,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Weiter'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dots(ThemeData theme) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < _pageCount; i++)
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i == _page
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
    ],
  );

  Widget _page0(ThemeData theme, IconData icon, String title, Widget body) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Icon(icon, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            body,
          ],
        ),
      );

  Widget _welcomePage(ThemeData theme) => _page0(
    theme,
    Icons.family_restroom,
    'Willkommen! 👋',
    Text(
      'Schön, dass du „Unser Familien-Organizer" nutzt. In wenigen Schritten '
      'ist alles eingerichtet: Nextcloud verbinden, Geburtstage festlegen und '
      'Erinnerungen aktivieren.',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyLarge,
    ),
  );

  Widget _connectPage(ThemeData theme, bool connected) => _page0(
    theme,
    connected ? Icons.cloud_done : Icons.cloud_outlined,
    'Mit Nextcloud verbinden',
    Column(
      children: [
        Text(
          connected
              ? 'Verbunden ✓ – deine Kalender und Aufgaben werden synchronisiert.'
              : 'Verbinde dein Nextcloud-Konto, damit Termine, Aufgaben und '
                    'Einkaufsliste auf allen Geräten synchron sind.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        if (!connected)
          FilledButton.icon(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ConnectionScreen())),
            icon: const Icon(Icons.login),
            label: const Text('Jetzt verbinden'),
          )
        else
          const Icon(Icons.check_circle, color: Colors.green, size: 40),
      ],
    ),
  );

  Widget _birthdayPage(ThemeData theme, bool connected) {
    final cfg =
        ref.watch(birthdayConfigProvider).value ?? const BirthdayConfig();
    final calendars = (ref.watch(collectionsProvider).value ?? const [])
        .where((c) => c.supportsEvents)
        .toList();
    return _page0(
      theme,
      Icons.cake_outlined,
      'Geburtstage',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Wähle den Kalender, in dem deine Geburtstage liegen. Dessen '
            'Einträge werden mit 👑 hervorgehoben.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (!connected)
            Text(
              'Erst verbinden – dann kannst du den Kalender wählen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            DropdownButtonFormField<String?>(
              initialValue: cfg.calendarHref,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Geburtstags-Kalender',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Keiner')),
                for (final c in calendars)
                  DropdownMenuItem(value: c.href, child: Text(c.displayName)),
              ],
              onChanged: (v) =>
                  ref.read(birthdayConfigProvider.notifier).setCalendar(v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auch aus anderen Quellen erkennen'),
              subtitle: const Text('z. B. Kontakte-Geburtstage / „Geburtstag"'),
              value: cfg.useHeuristic,
              onChanged: (v) =>
                  ref.read(birthdayConfigProvider.notifier).setUseHeuristic(v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _finishPage(ThemeData theme) => _page0(
    theme,
    Icons.notifications_active_outlined,
    'Erinnerungen & Sicherung',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Aktiviere Benachrichtigungen für Termine & fällige Aufgaben und '
          'eine automatische Sicherung in deiner Nextcloud.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (isAndroid)
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(notificationServiceProvider).requestPermission();
              await BatteryOptimization.request();
            },
            icon: const Icon(Icons.notifications),
            label: const Text('Benachrichtigungen erlauben'),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await ref.read(backupFrequencyProvider.notifier).set('weekly');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Wöchentliche Sicherung aktiviert.'),
                ),
              );
            }
          },
          icon: const Icon(Icons.cloud_sync_outlined),
          label: const Text('Wöchentliche Sicherung aktivieren'),
        ),
        const SizedBox(height: 16),
        Text(
          'Alles lässt sich später in den Einstellungen ändern.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
