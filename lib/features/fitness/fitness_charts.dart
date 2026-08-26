import 'package:flutter/material.dart';

/// Ein Wert im Diagramm. [label] erscheint nur an den Achsenenden.
class ChartValue {
  const ChartValue(this.label, this.value, {this.pending = false});

  final String label;
  final double value;

  /// Platzhalter für einen Tag, für den noch keine Daten vorliegen — wird gestrichelt
  /// gezeichnet statt gefüllt.
  ///
  /// Ohne ihn wirkt der letzte gefüllte Balken wie „heute", obwohl er der letzte Tag
  /// *mit Daten* ist. Genau da entsteht der falsche Eindruck, der gute Tag sei gestern
  /// gewesen.
  final bool pending;
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
      final wert = values[i];
      final v = wert.value;
      if (v <= 0) continue;
      final h = (v / maxValue) * size.height;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * slot + (slot - barWidth) / 2, size.height - h, barWidth, h),
        const Radius.circular(3),
      );

      if (wert.pending) {
        // Nur Umriss, gestrichelt: hier steht noch nichts fest.
        _dashedRRect(canvas, rect, goalColor);
        continue;
      }

      final reached = goal == null || v >= goal!;
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

/// Liniendiagramm für Verläufe mit echtem X-Abstand.
///
/// [smoothed] ist die durchgezogene Linie, [points] sind zusätzliche Einzelpunkte
/// (etwa Tageswerte unter einer geglätteten Gewichtskurve). Eines von beidem genügt.
class FitnessLineChart extends StatelessWidget {
  const FitnessLineChart({
    super.key,
    this.points = const [],
    this.smoothed = const [],
    this.goal,
    this.height = 170,
    this.minSpan = 0,
  });

  /// Kleinste dargestellte Spannweite. Nur dort setzen, wo winzige Schwankungen sonst
  /// dramatisch aussähen (Gewichtskurve) — bei Messkanälen würde es den Verlauf glätten.
  final double minSpan;

  /// Rohwerte als (Tagesabstand, Wert).
  final List<(int, double)> points;

  /// Geglätteter Verlauf, gleiche Form. Leer heißt: nur Rohwerte zeichnen.
  final List<(int, double)> smoothed;
  final double? goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Beide Reihen prüfen: die meisten Diagramme liefern nur die Linie und lassen
    // [points] leer.
    if (points.isEmpty && smoothed.isEmpty) return const SizedBox.shrink();
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
          minSpan: minSpan,
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
    required this.minSpan,
  });

  final double minSpan;
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

    // Robuste Skalierung über das 2.–98. Perzentil statt über Min und Max.
    //
    // Manche Spalten des Trackers enthalten einzelne Ausreißer um Größenordnungen —
    // PACE_spm schnellt im Stillstand auf sechsstellige Werte, VERTICAL_SPEED auf
    // ±1800. Über Min/Max skaliert, presst ein solcher Ausschlag die gesamte übrige
    // Kurve auf eine gerade Linie. Ausreißer werden gezeichnet, bestimmen den
    // Maßstab aber nicht.
    final sortiert = [...all]..sort();
    var min = _perzentil(sortiert, 0.02);
    var max = _perzentil(sortiert, 0.98);
    if (min == max) {
      min = all.reduce((a, b) => a < b ? a : b);
      max = all.reduce((a, b) => a > b ? a : b);
    }

    // Etwas Luft, und auf Wunsch ein Mindestbereich — sonst wird aus 300 Gramm
    // Schwankung eine dramatische Bergkette.
    final span = (max - min) < minSpan ? minSpan : (max - min);
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
    // Geklemmt, damit ein Ausreißer die Linie nicht aus dem Bild schiebt.
    double y(double v) => size.height -
        (((v - min) / range).clamp(-0.05, 1.05)) * size.height;

    if (goal != null && goal! >= min && goal! <= max) {
      _dashedLine(canvas, Offset(0, y(goal!)), Offset(size.width, y(goal!)), goalColor);
    }

    final dot = Paint()..color = rawColor;
    for (final p in points) {
      canvas.drawCircle(Offset(x(p.$1), y(p.$2)), 2.6, dot);
    }

    if (smoothed.length == 1) {
      final p = smoothed.first;
      canvas.drawCircle(Offset(x(p.$1), y(p.$2)), 4.5, Paint()..color = lineColor);
    } else if (smoothed.length > 1) {
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
      old.points != points ||
      old.smoothed != smoothed ||
      old.goal != goal ||
      old.minSpan != minSpan;
}

/// Gestrichelter Umriss eines Balkens.
void _dashedRRect(Canvas canvas, RRect rect, Color color) {
  final paint = Paint()
    ..color = color.withValues(alpha: 0.75)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3;

  final pfad = Path()..addRRect(rect);
  for (final metric in pfad.computeMetrics()) {
    var abstand = 0.0;
    while (abstand < metric.length) {
      final bis = (abstand + 4).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(abstand, bis), paint);
      abstand += 7;
    }
  }
}

double _perzentil(List<double> sortiert, double anteil) {
  if (sortiert.isEmpty) return 0;
  final i = ((sortiert.length - 1) * anteil).round().clamp(0, sortiert.length - 1);
  return sortiert[i];
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
