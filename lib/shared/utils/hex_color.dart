import 'package:flutter/material.dart';

/// Wandelt eine Nextcloud-Kalenderfarbe (`#RRGGBB` oder `#RRGGBBAA`) in eine
/// Flutter-[Color]. Gibt `null` zurück, wenn der Wert leer/ungültig ist.
Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 8) h = h.substring(0, 6); // RRGGBBAA → RRGGBB
  if (h.length != 6) return null;
  final value = int.tryParse(h, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
