import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/auth/account_providers.dart';
import '../members/member_settings.dart';
import 'calendar_event.dart';
import 'day_timeline.dart';
import 'event_actions.dart';
import 'event_editor_sheet.dart';
import 'event_providers.dart';

/// Anzeigemodus des Kalenders.
enum _CalView { month, day }

/// Kalender-Bereich (VEVENT per CalDAV): Monatsansicht mit Event-Markern
/// und einer Tagesliste der Termine des gewählten Tages, plus Tagesansicht
/// mit Stundenraster.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _format = CalendarFormat.month;
  _CalView _view = _CalView.month;

  // In UTC rechnen, damit Sommer-/Winterzeit-Wechsel die Tag-Indizes nicht um
  // einen Tag verschieben (sonst zeigt die Seite den Vortag).
  static final DateTime _epoch = DateTime.utc(2020, 1, 1);
  late PageController _dayPager;

  /// Uhrzeit, auf die die Tagesleiste beim Sprung scrollen soll (Startzeit des
  /// angetippten Termins). Nur für den Zieltag relevant.
  DateTime? _focusTime;

  int _pageOf(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).difference(_epoch).inDays;
  DateTime _dateOf(int page) => _epoch.add(Duration(days: page));

  @override
  void initState() {
    super.initState();
    _dayPager = PageController(initialPage: _pageOf(DateTime.now()));
  }

  @override
  void dispose() {
    _dayPager.dispose();
    super.dispose();
  }

  /// Wechselt in die Tagesansicht und zeigt [date]. Erzeugt dafür einen frischen
  /// PageController mit der Zielseite – damit garantiert der richtige Tag steht
  /// (auch nach vorherigem Blättern oder beim erneuten Öffnen).
  void _enterDay(DateTime date, {DateTime? focusTime}) {
    final old = _dayPager;
    _dayPager = PageController(initialPage: _pageOf(date));
    setState(() {
      _view = _CalView.day;
      _selectedDay = date;
      _focusedDay = date;
      _focusTime = focusTime;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Farb-Legende der Mitglieder, zugleich Schnellfilter (Tippen blendet
  /// einen Kalender ein/aus).
  Widget _legend(List<Member> members) {
    if (members.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final m in members)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilterChip(
                selected: !m.hidden,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                avatar: CircleAvatar(backgroundColor: m.color, radius: 7),
                label: Text(m.name),
                onSelected: (sel) => ref
                    .read(memberSettingsProvider.notifier)
                    .setHidden(m.href, !sel),
              ),
            ),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SegmentedButton<_CalView>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: _CalView.month,
            label: Text('Monat'),
            icon: Icon(Icons.calendar_month),
          ),
          ButtonSegment(
            value: _CalView.day,
            label: Text('Tag'),
            icon: Icon(Icons.view_day),
          ),
        ],
        selected: {_view},
        onSelectionChanged: (s) {
          if (s.first == _CalView.day) {
            _enterDay(DateTime.now()); // Tagesansicht startet immer bei heute.
          } else {
            setState(() => _view = s.first);
          }
        },
      ),
    );
  }

  Widget _dayHeader() {
    final label = DateFormat('EEEE, d. MMMM', 'de_DE').format(_selectedDay);
    final isToday = isSameDay(_selectedDay, DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Vorheriger Tag',
            onPressed: () => _dayPager.previousPage(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut),
          ),
          Expanded(
            child: Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächster Tag',
            onPressed: () => _dayPager.nextPage(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut),
          ),
          TextButton(
            onPressed: isToday
                ? null
                : () => _dayPager.jumpToPage(_pageOf(DateTime.now())),
            child: const Text('Heute'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(accountProvider);
    final eventsAsync = ref.watch(eventsControllerProvider);
    final eventsByDay = ref.watch(eventsByDayProvider);

    // Sprung-Anforderung von der Startseite (Termin/Countdown angetippt).
    final jump = ref.watch(calendarJumpProvider);
    if (jump != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(calendarJumpProvider.notifier).set(null);
        _enterDay(jump, focusTime: jump);
      });
    }

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
            onPressed: () => ref.invalidate(eventsControllerProvider),
          ),
        ],
      ),
      floatingActionButton: accountAsync.value != null
          ? FloatingActionButton(
              onPressed: () =>
                  showEventEditor(context, initialDay: _selectedDay),
              tooltip: 'Neuer Termin',
              child: const Icon(Icons.add),
            )
          : null,
      body: accountAsync.maybeWhen(
        orElse: () => const Center(child: CircularProgressIndicator()),
        data: (account) {
          if (account == null) return const _ConnectPrompt();
          // Tagesliste (Monatsmodus): am heutigen Tag bereits beendete Termine
          // ausblenden; vergangene Tage bleiben vollständig sichtbar.
          final listEvents = isSameDay(_selectedDay, DateTime.now())
              ? selectedEvents
                  .where((e) => !e.hasPassed(DateTime.now()))
                  .toList()
              : selectedEvents;
          return Column(
            children: [
              _viewToggle(),
              if (_view == _CalView.day) ...[
                _dayHeader(),
                Expanded(
                  child: eventsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _ErrorView(
                      message: '$e',
                      onRetry: () =>
                          ref.invalidate(eventsControllerProvider),
                    ),
                    data: (_) => PageView.builder(
                      // Key an den Controller binden: bei _enterDay wird ein
                      // frischer Controller erzeugt -> PageView baut neu auf und
                      // zeigt garantiert die Zielseite.
                      key: ValueKey(_dayPager),
                      controller: _dayPager,
                      onPageChanged: (i) => setState(() {
                        _selectedDay = _dateOf(i);
                        _focusedDay = _selectedDay;
                      }),
                      itemBuilder: (context, index) {
                        final date = _dateOf(index);
                        final dayEvents = eventsByDay[_dayKey(date)] ??
                            const <CalendarEvent>[];
                        final focus = (_focusTime != null &&
                                isSameDay(date, _focusTime!))
                            ? _focusTime
                            : null;
                        return DayTimeline(
                          day: date,
                          events: dayEvents,
                          focusTime: focus,
                          onEventLongPress: (e) =>
                              showEventActions(context, ref, e),
                          onCreateAt: (start) => showEventEditor(context,
                              initialStart: start),
                        );
                      },
                    ),
                  ),
                ),
              ] else ...[
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
              _legend(ref
                  .watch(membersProvider)
                  .where((m) => m.supportsEvents)
                  .toList()),
              const Divider(height: 1),
              Expanded(
                child: eventsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorView(
                    message: '$e',
                    onRetry: () => ref.invalidate(eventsControllerProvider),
                  ),
                  data: (_) => _DayEventList(
                    day: _selectedDay,
                    events: listEvents,
                    onEventLongPress: (e) => showEventActions(context, ref, e),
                  ),
                ),
              ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DayEventList extends StatelessWidget {
  const _DayEventList({
    required this.day,
    required this.events,
    required this.onEventLongPress,
  });
  final DateTime day;
  final List<CalendarEvent> events;
  final void Function(CalendarEvent event) onEventLongPress;

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
        final e = events[index - 1];
        return _EventTile(event: e, onLongPress: () => onEventLongPress(e));
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onLongPress});
  final CalendarEvent event;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.color ?? theme.colorScheme.primary;
    final hasLocation =
        event.location != null && event.location!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              SizedBox(width: 52, child: _timeBlock(theme, color)),
              Container(
                width: 4,
                height: 42,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (event.isMultiDay)
                      Text(_rangeLabel(),
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    if (hasLocation)
                      Text('📍 ${event.location}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (event.isRecurring)
                Icon(Icons.repeat,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeBlock(ThemeData theme, Color color) {
    if (event.allDay || event.isMultiDay) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event, size: 20, color: color),
          const SizedBox(height: 2),
          Text('ganztags',
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(DateFormat('HH:mm').format(event.start),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (event.end != null)
          Text(DateFormat('HH:mm').format(event.end!),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  String _rangeLabel() {
    final fmt = DateFormat('d. MMM', 'de_DE');
    return '${fmt.format(event.start)} – ${fmt.format(event.endDayInclusive)}';
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
