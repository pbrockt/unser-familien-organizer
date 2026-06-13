import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dekorativer Hintergrund aus weichen, organischen Pastell-Kreisen
/// (Planily-Stil). Wird hinter den Dashboard-Inhalt gelegt.
class BlobBackground extends StatelessWidget {
  const BlobBackground({super.key, this.opacity = 0.55});

  final double opacity;

  Widget _blob({
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
    return IgnorePointer(
      child: ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 45, sigmaY: 45),
          child: Stack(
            children: [
              _blob(
                  top: -70,
                  left: -50,
                  size: 230,
                  color: AppTheme.orange.withValues(alpha: opacity)),
              _blob(
                  top: 30,
                  right: -80,
                  size: 250,
                  color: AppTheme.sage.withValues(alpha: opacity)),
              _blob(
                  top: 300,
                  left: -60,
                  size: 210,
                  color: AppTheme.sky.withValues(alpha: opacity - 0.05)),
              _blob(
                  top: 380,
                  right: -50,
                  size: 190,
                  color: AppTheme.terracotta.withValues(alpha: opacity - 0.05)),
            ],
          ),
        ),
      ),
    );
  }
}
