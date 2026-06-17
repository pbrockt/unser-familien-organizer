import 'package:flutter/services.dart';

import 'platform_support.dart';

/// Brücke zum nativen Android-Code (MethodChannel), um die App von der
/// Akku-Optimierung auszunehmen. Damit wird der Hintergrund-Sync (und damit
/// Erinnerungen für anderswo angelegte Termine) zuverlässiger ausgeführt.
class BatteryOptimization {
  const BatteryOptimization._();

  static const _channel = MethodChannel('com.pbrockt.family_planner/battery');

  /// Ist die App bereits von der Akku-Optimierung ausgenommen? Auf nicht-Android
  /// (und bei Fehlern) `true`, da dort kein Akku-Doze greift.
  static Future<bool> isIgnoring() async {
    if (!isAndroid) return true;
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Öffnet den System-Dialog, um die App von der Akku-Optimierung auszunehmen.
  static Future<void> request() async {
    if (!isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      // Stillschweigend ignorieren – Status wird beim nächsten Öffnen geprüft.
    }
  }
}
