import 'package:flutter/material.dart';

/// Karte mit Überschrift und optionaler Erläuterung — die Grundform aller Sport-Blöcke.
class FitnessCard extends StatelessWidget {
  const FitnessCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// Karte, die eingeklappt startet — für Blöcke, die man selten braucht.
class FitnessExpandableCard extends StatelessWidget {
  const FitnessExpandableCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
        children: [child],
      ),
    );
  }
}

/// Beschriftete Werte im Fluss — passt sich der Breite an, statt in ein starres
/// Raster zu zwingen.
class FitnessValueGrid extends StatelessWidget {
  const FitnessValueGrid({super.key, required this.values});

  final List<(String, String)> values;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 22,
      runSpacing: 12,
      children: [
        for (final (label, value) in values)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              Text(value, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
      ],
    );
  }
}

/// Verteilung auf die vier Pulszonen als Balken mit Prozentangaben.
class FitnessZoneBar extends StatelessWidget {
  const FitnessZoneBar({
    super.key,
    required this.zoneSeconds,
    required this.labels,
  });

  final List<int> zoneSeconds;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final total = zoneSeconds.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return Text(
        'Keine Pulsdaten aufgezeichnet.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    // Von ruhig nach hart: die Abstufung soll ohne Legende lesbar sein.
    final farben = [
      scheme.primary.withValues(alpha: 0.35),
      scheme.primary,
      scheme.tertiary,
      scheme.error,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  if (zoneSeconds[i] > 0)
                    Expanded(
                      flex: zoneSeconds[i],
                      child: ColoredBox(color: farben[i]),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (var i = 0; i < 4; i++)
              if (zoneSeconds[i] > 0)
                Text(
                  '${labels[i]}: ${(zoneSeconds[i] * 100 / total).round()} % '
                  '(${_minuten(zoneSeconds[i])})',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: farben[i]),
                ),
          ],
        ),
      ],
    );
  }

  String _minuten(int sekunden) => '${(sekunden / 60).round()} min';
}

/// Erste, mittlere und letzte Beschriftung unter einem Verlaufsdiagramm.
class FitnessAxisLabels extends StatelessWidget {
  const FitnessAxisLabels({super.key, required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(labels.first, style: style),
          if (labels.length > 2) Text(labels[labels.length ~/ 2], style: style),
          if (labels.length > 1) Text(labels.last, style: style),
        ],
      ),
    );
  }
}
