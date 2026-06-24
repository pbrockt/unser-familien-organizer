import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'features/settings/reminder_sync.dart';
import 'features/settings/theme_provider.dart';
import 'shared/theme/app_theme.dart';

/// Wurzel-Widget. Bindet Router und Theme ein.
class FamilyPlannerApp extends ConsumerWidget {
  const FamilyPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final accent = ref.watch(accentColorProvider).value ?? AppTheme.orange;
    final amoled = ref.watch(amoledProvider).value ?? false;
    return MaterialApp.router(
      title: 'Unser Familien-Organizer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(seed: accent),
      darkTheme: AppTheme.dark(seed: accent, amoled: amoled),
      themeMode: themeMode,
      // Deutsche Lokalisierung: Datums-/Zeit-Picker auf Deutsch,
      // Wochenstart Montag.
      locale: const Locale('de'),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      // Hinweis: Der automatische Update-Check läuft im AppShell (dort gibt es
      // einen gültigen Navigator-Context für den Dialog), nicht hier im
      // builder – dessen Context hat keinen Navigator als Vorfahren.
      builder: (context, child) =>
          ReminderSync(child: child ?? const SizedBox()),
    );
  }
}
