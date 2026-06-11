import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'features/settings/reminder_sync.dart';
import 'shared/theme/app_theme.dart';

/// Wurzel-Widget. Bindet Router und Theme ein.
class FamilyPlannerApp extends ConsumerWidget {
  const FamilyPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'FamilyPlanner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      builder: (context, child) => ReminderSync(child: child ?? const SizedBox()),
    );
  }
}
