import 'package:flutter/services.dart';

import 'platform_support.dart';

const _channel = MethodChannel('com.pbrockt.family_planner/share');

/// Liefert den beim (Kalt-)Start geteilten Text (ACTION_SEND), sonst `null`.
/// Wird nach dem Abruf serverseitig geleert.
Future<String?> getInitialSharedText() async {
  if (!isAndroid) return null;
  try {
    return await _channel.invokeMethod<String>('getInitial');
  } catch (_) {
    return null;
  }
}

/// Registriert einen Handler für Text, der geteilt wird, während die App läuft.
void setSharedTextHandler(void Function(String text) onText) {
  if (!isAndroid) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'shared' && call.arguments is String) {
      final t = call.arguments as String;
      if (t.trim().isNotEmpty) onText(t);
    }
    return null;
  });
}
