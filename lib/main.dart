import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/background/background_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Deutsche Monats-/Wochentagsnamen für DateFormat & table_calendar.
  await initializeDateFormatting('de_DE', null);

  // Hintergrund-Sync initialisieren und – falls Erinnerungen aktiv sind –
  // den periodischen Task (re)registrieren.
  await initBackgroundSync();
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('notif_enabled') ?? false) {
    await registerBackgroundSync();
  }

  runApp(
    const ProviderScope(
      child: FamilyPlannerApp(),
    ),
  );
}
