import 'package:flutter/services.dart';

/// Ruft die native Widget-Diagnose auf (siehe FpWidgets.kt / MainActivity.kt).
/// Liefert einen lesbaren Bericht: platzierte Widgets, registrierte Provider,
/// gespeicherte Daten und ob das Anwenden der RemoteViews klappt.
const _channel = MethodChannel('com.pbrockt.family_planner/widget');

Future<String> widgetDiagnostics() async {
  try {
    final report = await _channel.invokeMethod<String>('diagnose');
    return report ?? '(keine Antwort)';
  } catch (e) {
    return 'Diagnose-Fehler: $e';
  }
}
