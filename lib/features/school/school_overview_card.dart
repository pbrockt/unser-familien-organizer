import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../calendar/calendar_event.dart';
import '../calendar/event_providers.dart';
import 'school_logic.dart';

/// Anstehende Schularbeiten für den Überblick auf der Startseite.
///
/// Zeigt sich nur, wenn welche anstehen — eine Dauer-Überschrift „Schularbeiten" ohne
/// Inhalt wäre auf der Startseite nur Ballast.
class SchoolOverviewCard extends ConsumerWidget {
  const SchoolOverviewCard({super.key, this.maxEintraege = 3});

  final int maxEintraege;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(homeBaseEventsProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final arbeiten = <CalendarEvent>[];
    for (final gruppe in groupExamsByPerson(events, today)) {
      arbeiten.addAll(gruppe.exams);
    }
    arbeiten.sort((a, b) => a.start.compareTo(b.start));
    if (arbeiten.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final arbeit in arbeiten.take(maxEintraege))
          _ArbeitKachel(
            arbeit: arbeit,
            today: today,
            offeneEinheiten: plannedSessions(events, arbeit, now),
          ),
      ],
    );
  }
}

class _ArbeitKachel extends StatelessWidget {
  const _ArbeitKachel({
    required this.arbeit,
    required this.today,
    required this.offeneEinheiten,
  });

  final CalendarEvent arbeit;
  final DateTime today;
  final int offeneEinheiten;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tage = DateTime(arbeit.start.year, arbeit.start.month, arbeit.start.day)
        .difference(today)
        .inDays;

    // Je näher der Termin, desto dringender die Farbe — bis zwei Tage vorher wird es
    // rot, denn dann hilft Lernen nur noch begrenzt.
    final farbe = tage <= 2
        ? scheme.error
        : (tage <= 6 ? scheme.tertiary : scheme.primary);

    final person = personOf(arbeit);
    final fach = subjectOf(arbeit.summary);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTap: () => context.go('/school'),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha:
                      Theme.of(context).brightness == Brightness.dark ? 0.25 : 0.08,
                ),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: farbe.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: Text(
                    _badge(tage),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: tage > 9 ? 15 : 13,
                      height: 1.05,
                      fontWeight: FontWeight.w700,
                      color: farbe,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '📝 $fach',
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _untertitel(person),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _badge(int tage) => switch (tage) {
        <= 0 => 'heute',
        1 => 'morgen',
        _ => '$tage\nTage',
      };

  String _untertitel(String person) {
    final datum = DateFormat('EEE, d. MMM', 'de_DE').format(arbeit.start);
    final wer = person == kNoPerson ? '' : '$person · ';
    // Ohne offene Einheiten ist der Lernplan entweder abgearbeitet oder es gab nie
    // einen — beides ist eine Aussage wert.
    final lernen = offeneEinheiten > 0
        ? ' · $offeneEinheiten Lern-${offeneEinheiten == 1 ? 'Einheit' : 'Einheiten'} offen'
        : '';
    return '$wer$datum$lernen';
  }
}
