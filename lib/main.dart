import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'core/background/background_sync.dart';
import 'core/platform/platform_support.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Deutsche Monats-/Wochentagsnamen für DateFormat & table_calendar.
  await initializeDateFormatting('de_DE', null);

  // SQLite auf dem Desktop (Windows/Linux/macOS) über FFI bereitstellen.
  if (isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Hintergrund-Sync (workmanager) gibt es nur auf Android.
  if (isAndroid) {
    await initBackgroundSync();
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('notif_enabled') ?? false) {
      await registerBackgroundSync();
    }
  }

  runApp(
    const ProviderScope(
      child: FamilyPlannerApp(),
    ),
  );
}
