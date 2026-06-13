import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Ruhiger, einfarbiger Hintergrund mit einem ganz leichten Farbverlauf und
/// sehr dezenten, kaum sichtbaren Kreisen – damit die Fläche nicht zu statisch
/// wirkt, aber nicht vom Inhalt ablenkt.
class BlobBackground extends StatelessWidget {
  const BlobBackground({super.key});

  Widget _circle({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final gradient = dark
        ? const [Color(0xFF2A2420), Color(0xFF211C18)]
        : const [Color(0xFFF8F4EC), Color(0xFFF0EADF)];
    return IgnorePointer(
      child: Stack(
        children: [
          // Ganz leichter Verlauf (hell: Creme, dunkel: warmes Anthrazit).
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradient,
              ),
            ),
            child: const SizedBox.expand(),
          ),
          // Sehr dezente, weich geblurrte Kreise.
          ClipRect(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Stack(
                children: [
                  _circle(
                      top: -50,
                      left: -40,
                      size: 230,
                      color: AppTheme.orange.withValues(alpha: 0.06)),
                  _circle(
                      top: 150,
                      right: -60,
                      size: 240,
                      color: AppTheme.sage.withValues(alpha: 0.05)),
                  _circle(
                      bottom: -70,
                      left: -30,
                      size: 220,
                      color: AppTheme.terracotta.withValues(alpha: 0.05)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
