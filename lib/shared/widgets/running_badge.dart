import 'package:flutter/material.dart';

/// Kleines grünes „läuft gerade"-Abzeichen für aktuell laufende Termine.
class RunningBadge extends StatelessWidget {
  const RunningBadge({super.key, this.compact = false});

  /// Kompakt = nur grüner Punkt + „läuft" (für enge Stellen wie Karten).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF2E9E5B);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: 2),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            compact ? 'läuft' : 'läuft gerade',
            style: const TextStyle(
              color: green,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
