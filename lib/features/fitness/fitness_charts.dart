import 'package:flutter/material.dart';

/// Ein Wert im Diagramm. [label] erscheint nur an den Achsenenden.
class ChartValue {
  const ChartValue(this.label, this.value);
  final String label;
  final double value;
}

/// Balkendiagramm mit optionaler Ziellinie.
///
/// Balken über dem Ziel werden hervorgehoben — beim Blick auf zwei Wochen soll auf einen
/// Griff erkennbar sein, an wie vielen Tagen es gereicht hat.
class FitnessBarChart extends StatelessWidget {
  const FitnessBarChart({
    super.key,
    required this.values,
    this.goal,
    this.height = 150,
    this.onTapIndex,
  });

  final List<ChartValue> values;
  final double? goal;
  final double height;
  final ValueChanged<int>? onTapIndex;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, c) => GestureDetector(
              onTapUp: onTapIndex == null
                  ? null
                  : (details) {
                      final slot = c.maxWidth / values.length;
                      final i = (details.localPosition.dx / slot).floor();
                      if (i >= 0 && i < values.length) onTapIndex!(i);
                    },
              child: CustomPaint(
                painter: _BarPainter(
                  values: values,
                  goal: goal,
                  barColor: scheme.primary,
                  barBelowColor: scheme.primary.withValues(alpha: 0.35),
                  goalColor: scheme.onSurfaceVariant,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        _AxisLabels(values: values),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.goal,
    required this.barColor,
    required this.barBelowColor,
    required this.goalColor,
  });

  final List<ChartValue> values;
  final double? goal;
  final Color barColor;
  final Color barBelowColor;
  final Color goalColor;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = [
      ...values.map((v) => v.value),
      ?goal,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    final slot = size.width / values.length;
    final barWidth = slot * 0.62;

    for (var i = 0; i < values.length; i++) {
      final v = values[i].value;
      if (v <= 0) continue;
      final h = (v / maxValue) * size.height;
      final reached = goal == null || v >= goal!;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * slot + (slot - barWidth) / 2, size.height - h, barWidth, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = reached ? barColor : barBelowColor);
    }

    if (goal != null) {
      final y = size.height - (goal! / maxValue) * size.height;
      _dashedLine(canvas, Offset(0, y), Offset(size.width, y), goalColor);
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.values != values || old.goal != goal || old.barColor != barColor;
}

/// Liniendiagramm für Verläufe mit echtem Tagesabstand.
class FitnessLineChart extends StatelessWidget {
  const FitnessLineChart({
    super.key,
    required this.points,
    this.smoothed = const [],
    this.goal,
    this.height = 170,
  });

  /// Rohwerte als (Tagesabstand, Wert).
  final List<(int, double)> points;

  /// Geglätteter Verlauf, gleiche Form. Leer heißt: nur Rohwerte zeichnen.
  final List<(int, double)> smoothed;
  final double? goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _LinePainter(
          points: points,
          smoothed: smoothed,
          goal: goal,
          rawColor: scheme.onSurfaceVariant.withValues(alpha: 0.55),
          lineColor: scheme.primary,
          goalColor: scheme.tertiary,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.smoothed,
    required this.goal,
    required this.rawColor,
    required this.lineColor,
    required this.goalColor,
  });

  final List<(int, double)> points;
  final List<(int, double)> smoothed;
  final double? goal;
  final Color rawColor;
  final Color lineColor;
  final Color goalColor;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [
      ...points.map((p) => p.$2),
      ...smoothed.map((p) => p.$2),
      ?goal,
    ];
    var min = all.reduce((a, b) => a < b ? a : b);
    var max = all.reduce((a, b) => a > b ? a : b);

    // Etwas Luft, und ein Mindestbereich — sonst wird aus 300 Gramm Schwankung eine
    // dramatische Bergkette.
    final span = (max - min) < 1.5 ? 1.5 : (max - min);
    final mid = (max + min) / 2;
    min = mid - span / 2 - span * 0.1;
    max = mid + span / 2 + span * 0.1;
    final range = (max - min) < 0.1 ? 0.1 : (max - min);

    final maxDay = [
      ...points.map((p) => p.$1),
      ...smoothed.map((p) => p.$1),
      1,
    ].reduce((a, b) => a > b ? a : b);

    double x(int day) => day / maxDay * size.width;
    double y(double v) => size.height - ((v - min) / range) * size.height;

    if (goal != null && goal! >= min && goal! <= max) {
      _dashedLine(canvas, Offset(0, y(goal!)), Offset(size.width, y(goal!)), goalColor);
    }

    final dot = Paint()..color = rawColor;
    for (final p in points) {
      canvas.drawCircle(Offset(x(p.$1), y(p.$2)), 2.6, dot);
    }

    if (smoothed.length > 1) {
      final path = Path();
      for (var i = 0; i < smoothed.length; i++) {
        final o = Offset(x(smoothed[i].$1), y(smoothed[i].$2));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      final last = smoothed.last;
      canvas.drawCircle(Offset(x(last.$1), y(last.$2)), 4.5, Paint()..color = lineColor);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.points != points || old.smoothed != smoothed || old.goal != goal;
}

void _dashedLine(Canvas canvas, Offset from, Offset to, Color color) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = 1.2;
  const dash = 6.0;
  const gap = 5.0;
  var x = from.dx;
  while (x < to.dx) {
    canvas.drawLine(Offset(x, from.dy), Offset((x + dash).clamp(0, to.dx), to.dy), paint);
    x += dash + gap;
  }
}

class _AxisLabels extends StatelessWidget {
  const _AxisLabels({required this.values});

  final List<ChartValue> values;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(values.first.label, style: style),
          if (values.length > 2) Text(values[values.length ~/ 2].label, style: style),
          if (values.length > 1) Text(values.last.label, style: style),
        ],
      ),
    );
  }
}
