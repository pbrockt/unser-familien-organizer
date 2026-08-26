import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'fitness_models.dart';

/// Zeigt die gefahrene Strecke auf einer OpenStreetMap-Karte.
///
/// Die Linie ist nach Geschwindigkeit eingefärbt: blass, wo es langsam ging, kräftig, wo
/// es lief. Start und Ziel sind eigens markiert.
///
/// Ohne Netz bleiben die Kacheln grau — deshalb wird die Strecke **zusätzlich** als
/// eigenständige Zeichnung angeboten ([FitnessRouteSketch]), die ohne Kartendienst
/// auskommt. Umschalten geht über die Schaltfläche oben rechts.
class FitnessRouteMap extends StatefulWidget {
  const FitnessRouteMap({super.key, required this.points, this.height = 260});

  final List<TrackPoint> points;
  final double height;

  @override
  State<FitnessRouteMap> createState() => _FitnessRouteMapState();
}

class _FitnessRouteMapState extends State<FitnessRouteMap> {
  bool _karte = true;

  @override
  Widget build(BuildContext context) {
    final track = widget.points
        .where((p) => p.lat != null && p.lon != null)
        .toList(growable: false);
    if (track.length < 2) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final koordinaten = [for (final p in track) LatLng(p.lat!, p.lon!)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _karte
                ? FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.coordinates(
                        coordinates: koordinaten,
                        padding: const EdgeInsets.all(28),
                      ),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.pinchZoom |
                            InteractiveFlag.drag |
                            InteractiveFlag.doubleTapZoom,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        // Von der OSM-Nutzungsrichtlinie verlangt: die Anfragen müssen
                        // sich einer App zuordnen lassen.
                        userAgentPackageName: 'com.pbrockt.family_planner',
                        maxNativeZoom: 19,
                      ),
                      PolylineLayer(
                        polylines: _abschnitte(track, scheme),
                      ),
                      MarkerLayer(
                        markers: [
                          _punkt(koordinaten.first, scheme.tertiary),
                          _punkt(koordinaten.last, scheme.error),
                        ],
                      ),
                      const _OsmHinweis(),
                    ],
                  )
                : FitnessRouteSketch(points: track),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _karte = !_karte),
            icon: Icon(_karte ? Icons.timeline : Icons.map_outlined, size: 18),
            label: Text(_karte ? 'Ohne Karte' : 'Mit Karte'),
          ),
        ),
      ],
    );
  }

  Marker _punkt(LatLng pos, Color farbe) => Marker(
        point: pos,
        width: 16,
        height: 16,
        child: Container(
          decoration: BoxDecoration(
            color: farbe,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      );

  /// Zerlegt die Strecke in kurze Abschnitte, damit sich die Farbe dem Tempo folgend
  /// ändern kann — eine einzelne Polylinie kennt nur eine Farbe.
  List<Polyline> _abschnitte(List<TrackPoint> track, ColorScheme scheme) {
    final maxSpeed = track.map((p) => p.speedKmh).reduce(math.max);
    final langsam = scheme.primary.withValues(alpha: 0.45);
    final schnell = scheme.primary;

    return [
      for (var i = 1; i < track.length; i++)
        Polyline(
          points: [
            LatLng(track[i - 1].lat!, track[i - 1].lon!),
            LatLng(track[i].lat!, track[i].lon!),
          ],
          strokeWidth: 4.5,
          color: Color.lerp(
            langsam,
            schnell,
            maxSpeed <= 0 ? 0.0 : (track[i].speedKmh / maxSpeed).clamp(0.0, 1.0),
          )!,
        ),
    ];
  }
}

/// Pflichtangabe für OpenStreetMap-Kacheln.
class _OsmHinweis extends StatelessWidget {
  const _OsmHinweis();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        color: Colors.white70,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: const Text(
          '© OpenStreetMap',
          style: TextStyle(fontSize: 9, color: Colors.black87),
        ),
      ),
    );
  }
}

/// Streckenverlauf ohne Kartendienst — funktioniert offline.
class FitnessRouteSketch extends StatelessWidget {
  const FitnessRouteSketch({super.key, required this.points});

  final List<TrackPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _SketchPainter(
        track: points,
        slow: scheme.primary.withValues(alpha: 0.45),
        fast: scheme.primary,
        start: scheme.tertiary,
        end: scheme.error,
      ),
      size: Size.infinite,
    );
  }
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({
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
    if (track.length < 2) return;

    final lats = track.map((p) => p.lat!).toList();
    final lons = track.map((p) => p.lon!).toList();
    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLon = lons.reduce(math.min);
    final maxLon = lons.reduce(math.max);

    // Längengrade schrumpfen mit dem Breitengrad — ohne diesen Faktor wäre die Strecke
    // in unseren Breiten deutlich zu breit gezeichnet.
    final lonFaktor = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final spanLat = (maxLat - minLat).abs();
    final spanLon = (maxLon - minLon).abs() * lonFaktor;
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
      final anteil =
          maxSpeed <= 0 ? 0.0 : (track[i].speedKmh / maxSpeed).clamp(0.0, 1.0);
      canvas.drawLine(
        punkt(track[i - 1]),
        punkt(track[i]),
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
  bool shouldRepaint(_SketchPainter old) => old.track != track;
}
