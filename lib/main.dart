import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
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

  // Hintergrund-Sync (workmanager) gibt es nur auf Android. Immer registrieren,
  // damit sich die Home-Widgets auch ohne aktive Benachrichtigungen regelmäßig
  // aktualisieren (Erinnerungen werden im Task nur bei Bedarf geplant).
  if (isAndroid) {
    await initBackgroundSync();
    await registerBackgroundSync();
  }

  runApp(const ProviderScope(child: FamilyPlannerApp()));
}
