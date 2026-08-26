import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'fitness_models.dart';

/// Zeichnet die gefahrene Strecke aus den Koordinaten der CSV.
///
/// Bewusst ohne Kartendienst: echte Kartenkacheln bräuchten eine zusätzliche
/// Abhängigkeit, eine Netzverbindung und einen Kachel-Anbieter mit Nutzungsbedingungen.
/// Der Streckenverlauf allein beantwortet die Frage „wo bin ich langgefahren?" für eine
/// bekannte Gegend gut genug — und funktioniert offline.
///
/// Eingefärbt nach Geschwindigkeit, damit man sieht, wo es zügig lief und wo nicht.
class FitnessRouteMap extends StatelessWidget {
  const FitnessRouteMap({super.key, required this.points, this.height = 220});

  final List<TrackPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final track =
        points.where((p) => p.lat != null && p.lon != null).toList(growable: false);
    if (track.length < 2) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _RoutePainter(
          track: track,
          slow: scheme.primary.withValues(alpha: 0.45),
          fast: scheme.primary,
          start: scheme.tertiary,
          end: scheme.error,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.track,
    required this.slow,
    required this.fast,
    required this.start,
    required this.end,
  });

  final List<TrackPoint> track;
  final Color slow;
  final Color fast;
  final Color start;
  final Color end;

  @override
  void paint(Canvas canvas, Size size) {
    final lats = track.map((p) => p.lat!).toList();
    final lons = track.map((p) => p.lon!).toList();
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLon = lons.reduce(math.min);
    final maxLon = lons.reduce(math.max);

    // Längengrade schrumpfen mit dem Breitengrad — ohne diesen Faktor wäre die Strecke
    // in unseren Breiten deutlich zu breit gezeichnet.
    final latMitte = (minLat + maxLat) / 2;
    final lonFaktor = math.cos(latMitte * math.pi / 180);

    final spanLat = (maxLat - minLat).abs();
    final spanLon = (maxLon - minLon).abs() * lonFaktor;
    // Sehr kurze Strecken sonst durch Division nahe null verzerrt.
    final span = math.max(math.max(spanLat, spanLon), 0.0002);

    const rand = 14.0;
    final flaeche = math.min(size.width, size.height) - rand * 2;
    final offsetX = (size.width - flaeche) / 2;
    final offsetY = (size.height - flaeche) / 2;

    Offset punkt(TrackPoint p) {
      final x = ((p.lon! - minLon) * lonFaktor - spanLon / 2) / span + 0.5;
      // Norden nach oben: die y-Achse der Leinwand zeigt nach unten.
      final y = 1 - (((p.lat! - minLat) - spanLat / 2) / span + 0.5);
      return Offset(offsetX + x * flaeche, offsetY + y * flaeche);
    }

    final maxSpeed = track.map((p) => p.speedKmh).reduce(math.max);

    for (var i = 1; i < track.length; i++) {
      final a = punkt(track[i - 1]);
      final b = punkt(track[i]);
      final anteil = maxSpeed <= 0 ? 0.0 : (track[i].speedKmh / maxSpeed).clamp(0.0, 1.0);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Color.lerp(slow, fast, anteil)!
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(punkt(track.first), 5.5, Paint()..color = start);
    canvas.drawCircle(punkt(track.last), 5.5, Paint()..color = end);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.track != track;
}
