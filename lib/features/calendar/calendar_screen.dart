import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/auth/account_providers.dart';
import 'calendar_event.dart';
import 'event_providers.dart';

/// Kalender-Bereich (VEVENT per CalDAV): Monatsansicht mit Event-Markern
/// und einer Tagesliste der Termine des gewählten Tages.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(accountProvider);
    final eventsAsync = ref.watch(eventsProvider);
    final eventsByDay = ref.watch(eventsByDayProvider);

    List<CalendarEvent> loader(DateTime day) =>
        eventsByDay[_dayKey(day)] ?? const [];

    final selectedEvents = loader(_selectedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(eventsProvider),
          ),
        ],
      ),
      body: accountAsync.maybeWhen(
        orElse: () => const Center(child: CircularProgressIndicator()),
        data: (account) {
          if (account == null) return const _ConnectPrompt();
          return Column(
            children: [
              TableCalendar<CalendarEvent>(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                locale: 'de_DE',
                startingDayOfWeek: StartingDayOfWeek.monday,
                calendarFormat: _format,
                availableCalendarFormats: const {
                  CalendarFormat.month: 'Monat',
                  CalendarFormat.twoWeeks: '2 Wochen',
                  CalendarFormat.week: 'Woche',
                },
                selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
                eventLoader: loader,
                onFormatChanged: (f) => setState(() => _format = f),
                onPageChanged: (day) => _focusedDay = day,
                onDaySelected: (selected, focused) => setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                }),
                calendarStyle: CalendarStyle(
                  markersMaxCount: 4,
                  todayDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  todayTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                  selectedDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                calendarBuilders: CalendarBuilders<CalendarEvent>(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return null;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: events.take(4).map((e) {
                        return Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: e.color ??
                                Theme.of(context).colorScheme.primary,
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: eventsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorView(
                    message: '$e',
                    onRetry: () => ref.invalidate(eventsProvider),
                  ),
                  data: (_) => _DayEventList(
                    day: _selectedDay,
                    events: selectedEvents,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayEventList extends StatelessWidget {
  const _DayEventList({required this.day, required this.events});
  final DateTime day;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final header = DateFormat('EEEE, d. MMMM', 'de_DE').format(day);
    if (events.isEmpty) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(header,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Keine Termine an diesem Tag.')),
          ),
        ],
      );
    }
    return ListView.builder(
      itemCount: events.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(header,
                style: Theme.of(context).textTheme.titleSmall),
          );
        }
        return _EventTile(event: events[index - 1]);
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});
  final CalendarEvent event;

  String _timeLabel() {
    if (event.allDay) return 'Ganztägig';
    final start = DateFormat('HH:mm').format(event.start);
    if (event.end == null) return start;
    final end = DateFormat('HH:mm').format(event.end!);
    return '$start – $end';
  }

  @override
  Widget build(BuildContext context) {
    final color = event.color ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 6,
          height: double.infinity,
          color: color,
        ),
        title: Text(event.summary),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_timeLabel()),
            if (event.location != null && event.location!.isNotEmpty)
              Text('📍 ${event.location}'),
          ],
        ),
        trailing: event.isRecurring
            ? const Icon(Icons.repeat, size: 18)
            : null,
        isThreeLine:
            event.location != null && event.location!.isNotEmpty,
      ),
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Nicht verbunden', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Verbinde im Tab „Familie" deine Nextcloud, '
              'um Termine zu sehen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Erneut versuchen'),
            ),
          ],
        ),
      ),
    );
  }
}
