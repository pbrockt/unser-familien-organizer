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

/// Wandelt eine [Color] in `#RRGGBB` (ohne Alpha). Für die Übergabe von
/// Kalenderfarben an die nativen Home-Widgets.
String toHexRgb(Color c) {
  int channel(double x) => (x * 255).round().clamp(0, 255);
  String two(int v) => v.toRadixString(16).padLeft(2, '0');
  return '#${two(channel(c.r))}${two(channel(c.g))}${two(channel(c.b))}';
}
