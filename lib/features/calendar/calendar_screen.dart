import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/auth/account_providers.dart';
import '../../shared/utils/week.dart';
import '../../shared/widgets/blob_background.dart';
import '../../shared/widgets/running_badge.dart';
import '../members/member_settings.dart';
import '../search/search_screen.dart';
import '../weather/weather_service.dart';
import 'birthdays.dart';
import 'calendar_event.dart';
import 'calendar_presets.dart';
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
    ref.read(calendarSelectedDayProvider.notifier).set(date);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Farb-Legende der Mitglieder, zugleich Schnellfilter (Tippen blendet
  /// einen Kalender ein/aus).
  Widget _legend(WidgetRef ref, List<Member> members) {
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

  /// Ist [p] aktuell aktiv? (Sichtbare Kalender = Preset-Kalender, bezogen auf
  /// die existierenden Event-Kalender.)
  bool _presetActive(CalendarPreset p, List<Member> calendars) {
    final visibleNow = calendars
        .where((m) => !m.hidden)
        .map((m) => m.href)
        .toSet();
    final presetVisible = p.visibleHrefs
        .where((h) => calendars.any((m) => m.href == h))
        .toSet();
    return visibleNow.length == presetVisible.length &&
        visibleNow.containsAll(presetVisible);
  }

  /// Wendet ein Preset an: blendet alle nicht enthaltenen Kalender aus.
  Future<void> _applyPreset(CalendarPreset p, List<Member> calendars) async {
    final notifier = ref.read(memberSettingsProvider.notifier);
    for (final m in calendars) {
      await notifier.setHidden(m.href, !p.visibleHrefs.contains(m.href));
    }
  }

  /// Filter-Preset-Leiste: ein Chip je Preset (Tippen = anwenden, lange drücken
  /// = löschen) plus „+ Filter" zum Anlegen eines neuen Presets.
  Widget _presetBar(WidgetRef ref, List<Member> calendars) {
    if (calendars.length < 2) return const SizedBox.shrink();
    final presets = ref.watch(calendarPresetsProvider).value ?? const [];
    final allVisible = calendars.every((m) => !m.hidden);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          // „Alle"-Chip blendet wieder alle Kalender ein.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              selected: allVisible,
              label: const Text('Alle'),
              visualDensity: VisualDensity.compact,
              onSelected: (_) async {
                final notifier = ref.read(memberSettingsProvider.notifier);
                for (final m in calendars) {
                  await notifier.setHidden(m.href, false);
                }
              },
            ),
          ),
          for (final p in presets)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onLongPress: () => _deletePreset(p),
                child: ChoiceChip(
                  selected: _presetActive(p, calendars),
                  label: Text(p.name),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _applyPreset(p, calendars),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Filter'),
              visualDensity: VisualDensity.compact,
              onPressed: () => _createPreset(calendars),
            ),
          ),
        ],
      ),
    );
  }

  /// Blendet die Filter (Presets + Kalender-Legende) in einem Bottom-Sheet ein –
  /// hält den Kalender-Tab aufgeräumt (statt zwei Dauer-Zeilen).
  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Consumer(
        builder: (context, ref, _) {
          final calendars = ref
              .watch(membersProvider)
              .where((m) => m.supportsEvents)
              .toList();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.filter_alt_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Filter',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _presetBar(ref, calendars),
                  _legend(ref, calendars),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Dialog zum Anlegen/Überschreiben eines Filter-Presets (Name + Kalenderwahl,
  /// vorausgewählt nach aktueller Sichtbarkeit).
  Future<void> _createPreset(List<Member> calendars) async {
    final ctrl = TextEditingController();
    final selected = {for (final m in calendars) m.href: !m.hidden};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Filter-Preset'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Name (z. B. Arbeit)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in calendars)
                        CheckboxListTile(
                          dense: true,
                          value: selected[m.href] ?? false,
                          onChanged: (v) =>
                              setS(() => selected[m.href] = v ?? false),
                          secondary: CircleAvatar(
                            backgroundColor: m.color,
                            radius: 8,
                          ),
                          title: Text(m.name),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      final name = ctrl.text.trim();
      if (name.isEmpty) return;
      final visible = {
        for (final e in selected.entries)
          if (e.value) e.key,
      };
      await ref
          .read(calendarPresetsProvider.notifier)
          .addOrUpdate(name, visible);
      await _applyPreset(
        CalendarPreset(name: name, visibleHrefs: visible),
        calendars,
      );
    }
  }

  Future<void> _deletePreset(CalendarPreset p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('„${p.name}" löschen?'),
        content: const Text('Das Filter-Preset wird entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(calendarPresetsProvider.notifier).remove(p.name);
    }
  }

  /// Kleines Wetter-Badge (Icon + Max/Min) für einen Tag, falls eine Vorhersage
  /// vorliegt – sonst leer.
  Widget _weatherBadge(DateTime day) {
    final data = ref.watch(weatherProvider).value;
    if (data == null || data.isEmpty) return const SizedBox.shrink();
    final key = DateFormat('yyyy-MM-dd').format(day);
    final w = data[key];
    if (w == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(weatherIcon(w.code), size: 18, color: scheme.primary),
        const SizedBox(width: 4),
        Text(
          '${w.tempMax.round()}° / ${w.tempMin.round()}°',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// Kompakter Monat/Tag-Umschalter – sitzt in der AppBar (spart eine Zeile).
  Widget _viewToggle() {
    return Center(
      child: SegmentedButton<_CalView>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          textStyle: const TextStyle(fontSize: 12),
        ),
        segments: const [
          ButtonSegment(value: _CalView.month, label: Text('Monat')),
          ButtonSegment(value: _CalView.day, label: Text('Tag')),
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
              curve: Curves.easeOut,
            ),
          ),
          Expanded(
            child: Text(
              'KW ${isoWeekNumber(_selectedDay)} · $label',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: _headerTitleStyle(context),
            ),
          ),
          // Wetter nur rechts.
          _weatherBadge(_selectedDay),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächster Tag',
            onPressed: () => _dayPager.nextPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
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

  /// Gemeinsamer Titelstil für Tages- und Monatskopf (gleiche Schriftgröße).
  TextStyle? _headerTitleStyle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium;

  /// Wechselt den angezeigten Monat um [delta] (−1/+1), geklemmt auf den
  /// erlaubten Bereich – der TableCalendar folgt dem geänderten `focusedDay`.
  void _shiftMonth(int delta) {
    final target = DateTime(_focusedDay.year, _focusedDay.month + delta, 1);
    final min = DateTime(2020, 1, 1);
    final max = DateTime(2035, 12, 31);
    setState(() {
      _focusedDay = target.isBefore(min)
          ? min
          : (target.isAfter(max) ? max : target);
    });
  }

  /// Kopfzeile der Monatsansicht – analog zur Tagesansicht: ‹ ›-Pfeile für
  /// Vor-/Folgemonat, mittig der Monatsname, plus „Heute".
  Widget _monthHeader() {
    final label = DateFormat('MMMM yyyy', 'de_DE').format(_focusedDay);
    final now = DateTime.now();
    final isCurrentMonth =
        _focusedDay.year == now.year && _focusedDay.month == now.month;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Vorheriger Monat',
            onPressed: () => _shiftMonth(-1),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: _headerTitleStyle(context),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächster Monat',
            onPressed: () => _shiftMonth(1),
          ),
          TextButton(
            onPressed: isCurrentMonth
                ? null
                : () {
                    final today = DateTime.now();
                    setState(() {
                      _selectedDay = today;
                      _focusedDay = today;
                    });
                    ref.read(calendarSelectedDayProvider.notifier).set(today);
                  },
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
    final eventCalendars = ref
        .watch(membersProvider)
        .where((m) => m.supportsEvents)
        .toList();
    // Ist gerade gefiltert? (Mind. ein Kalender ausgeblendet.)
    final filterActive = eventCalendars.any((m) => m.hidden);

    // Sprung-Anforderung von der Startseite.
    final jump = ref.watch(calendarJumpProvider);
    if (jump != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(calendarJumpProvider.notifier).set(null);
        if (jump.openDay) {
          // Termin/Countdown → Tagesansicht zum Zeitpunkt.
          _enterDay(jump.date, focusTime: jump.date);
        } else {
          // 2-Wochen-Übersicht → nur im Monat anspringen.
          setState(() {
            _view = _CalView.month;
            _selectedDay = jump.date;
            _focusedDay = jump.date;
          });
          ref.read(calendarSelectedDayProvider.notifier).set(jump.date);
        }
      });
    }

    List<CalendarEvent> loader(DateTime day) =>
        eventsByDay[_dayKey(day)] ?? const [];

    final selectedEvents = loader(_selectedDay);
    final birthdayCfg =
        ref.watch(birthdayConfigProvider).value ?? const BirthdayConfig();

    // Verlauf hinter das ganze Scaffold legen (wie auf der Startseite), damit
    // AppBar + Inhalt ohne manuellen Offset bündig sitzen.
    return Stack(
      children: [
        const Positioned.fill(child: BlobBackground()),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Kalender'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            actions: [
              _viewToggle(),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Suchen',
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
              ),
              if (eventCalendars.length >= 2)
                IconButton(
                  tooltip: 'Filter',
                  isSelected: filterActive,
                  icon: const Icon(Icons.filter_alt_outlined),
                  selectedIcon: const Icon(Icons.filter_alt),
                  onPressed: () => _showFilterSheet(),
                ),
              IconButton(
                tooltip: 'Aktualisieren',
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(eventsControllerProvider),
              ),
            ],
          ),
          body: accountAsync.maybeWhen(
            orElse: () => const Center(child: CircularProgressIndicator()),
            data: (account) {
              if (account == null) return const _ConnectPrompt();
              return Column(
                children: [
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
                          onPageChanged: (i) {
                            setState(() {
                              _selectedDay = _dateOf(i);
                              _focusedDay = _selectedDay;
                            });
                            ref
                                .read(calendarSelectedDayProvider.notifier)
                                .set(_selectedDay);
                          },
                          itemBuilder: (context, index) {
                            final date = _dateOf(index);
                            final dayEvents =
                                eventsByDay[_dayKey(date)] ??
                                const <CalendarEvent>[];
                            final focus =
                                (_focusTime != null &&
                                    isSameDay(date, _focusTime!))
                                ? _focusTime
                                : null;
                            return DayTimeline(
                              day: date,
                              events: dayEvents,
                              focusTime: focus,
                              onEventLongPress: (e) =>
                                  showEventActions(context, ref, e),
                              onCreateAt: (start) =>
                                  showEventEditor(context, initialStart: start),
                            );
                          },
                        ),
                      ),
                    ),
                  ] else ...[
                    // Kalender + Terminliste scrollen gemeinsam als eine Seite
                    // (der Kalender scrollt mit nach oben weg).
                    Expanded(
                      child: ListView(
                        children: [
                          // Eigene Kopfzeile (Pfeile + „Heute") wie in der
                          // Tagesansicht – statt der eingebauten Zeile.
                          _monthHeader(),
                          TableCalendar<CalendarEvent>(
                            firstDay: DateTime.utc(2020, 1, 1),
                            lastDay: DateTime.utc(2035, 12, 31),
                            headerVisible: false,
                            focusedDay: _focusedDay,
                            locale: 'de_DE',
                            startingDayOfWeek: StartingDayOfWeek.monday,
                            calendarFormat: _format,
                            // Etwas kompakter, damit der Kalender weniger Höhe
                            // einnimmt (Default-Zeilenhöhe 52 → 46).
                            rowHeight: 46,
                            daysOfWeekHeight: 18,
                            // Kalenderwochen-Spalte links anzeigen.
                            weekNumbersVisible: true,
                            // Nur Monatsansicht – kein Umschalter (2 Wochen/Woche).
                            availableCalendarFormats: const {
                              CalendarFormat.month: 'Monat',
                            },
                            headerStyle: const HeaderStyle(
                              formatButtonVisible: false,
                            ),
                            // KW gleich gedämpft wie die Wochentags-Beschriftung.
                            daysOfWeekStyle: DaysOfWeekStyle(
                              weekdayStyle: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              weekendStyle: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            selectedDayPredicate: (d) =>
                                isSameDay(d, _selectedDay),
                            eventLoader: loader,
                            onFormatChanged: (f) => setState(() => _format = f),
                            onPageChanged: (day) => _focusedDay = day,
                            onDaySelected: (selected, focused) {
                              setState(() {
                                _selectedDay = selected;
                                _focusedDay = focused;
                              });
                              ref
                                  .read(calendarSelectedDayProvider.notifier)
                                  .set(selected);
                            },
                            calendarStyle: CalendarStyle(
                              markersMaxCount: 4,
                              weekNumberTextStyle: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              // Tage des aktuellen Monats leicht hinterlegen, Tage außerhalb
                              // klar abgesetzt (blasser, ohne Hintergrund).
                              defaultDecoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.035),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              weekendDecoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.035),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              outsideDecoration: const BoxDecoration(
                                color: Colors.transparent,
                              ),
                              outsideTextStyle: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.32),
                              ),
                              todayDecoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              todayTextStyle: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                              selectedDecoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            calendarBuilders: CalendarBuilders<CalendarEvent>(
                              markerBuilder: (context, day, events) {
                                if (events.isEmpty) return null;
                                final now = DateTime.now();
                                final today = DateTime(
                                  now.year,
                                  now.month,
                                  now.day,
                                );
                                final dayOnly = DateTime(
                                  day.year,
                                  day.month,
                                  day.day,
                                );
                                final pastDay = dayOnly.isBefore(today);
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: events.take(4).map((e) {
                                    // Vergangene Tage – und heute bereits erledigte
                                    // Termine – nur noch schwach sichtbar.
                                    final faint =
                                        pastDay ||
                                        (dayOnly == today && e.hasPassed(now));
                                    // Geburtstage als Krone statt Punkt – in fester
                                    // Box, damit sie die Marker-Reihe nicht höher
                                    // zieht als die Punkte.
                                    if (isBirthday(e, birthdayCfg)) {
                                      return Opacity(
                                        opacity: faint ? 0.3 : 1,
                                        child: const SizedBox(
                                          width: 11,
                                          height: 8,
                                          child: FittedBox(
                                            fit: BoxFit.contain,
                                            child: Text(
                                              '👑',
                                              style: TextStyle(height: 1),
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    final base =
                                        e.color ??
                                        Theme.of(context).colorScheme.primary;
                                    return Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: base.withValues(
                                          alpha: faint ? 0.3 : 1,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ),
                          eventsAsync.when(
                            loading: () => const Padding(
                              padding: EdgeInsets.all(32),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            error: (e, _) => _ErrorView(
                              message: '$e',
                              onRetry: () =>
                                  ref.invalidate(eventsControllerProvider),
                            ),
                            data: (_) => _DayEventList(
                              day: _selectedDay,
                              events: selectedEvents,
                              weather: _weatherBadge(_selectedDay),
                              birthdayConfig: birthdayCfg,
                              onEventLongPress: (e) =>
                                  showEventActions(context, ref, e),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DayEventList extends StatelessWidget {
  const _DayEventList({
    required this.day,
    required this.events,
    required this.onEventLongPress,
    required this.birthdayConfig,
    this.weather = const SizedBox.shrink(),
  });
  final DateTime day;
  final List<CalendarEvent> events;
  final void Function(CalendarEvent event) onEventLongPress;
  final BirthdayConfig birthdayConfig;
  final Widget weather;

  @override
  Widget build(BuildContext context) {
    final header = DateFormat('EEEE, d. MMMM', 'de_DE').format(day);
    if (events.isEmpty) {
      return ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    header,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                weather,
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('Keine Termine an diesem Tag.')),
          ),
        ],
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(header, style: Theme.of(context).textTheme.titleSmall),
          );
        }
        final e = events[index - 1];
        // Am heutigen Tag bereits beendete Termine eingeklappt + transparent
        // zeigen (statt ausblenden).
        final passed =
            isSameDay(day, DateTime.now()) && e.hasPassed(DateTime.now());
        return _EventTile(
          event: e,
          day: day,
          passed: passed,
          birthdayConfig: birthdayConfig,
          onLongPress: () => onEventLongPress(e),
        );
      },
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.day,
    required this.onLongPress,
    required this.birthdayConfig,
    this.passed = false,
  });
  final CalendarEvent event;

  /// Tag, an dem dieser Eintrag in der Liste steht (für mehrtägige Termine).
  final DateTime day;
  final VoidCallback onLongPress;
  final BirthdayConfig birthdayConfig;

  /// Bereits beendeter Termin (heute) → eingeklappt + leicht durchsichtig.
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = event.color ?? theme.colorScheme.primary;
    final hasLocation = event.location != null && event.location!.isNotEmpty;

    if (passed) return _buildPassed(context, theme, color);

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
                      isBirthday(event, birthdayConfig)
                          ? '👑 ${withBirthdayAge(event.summary, event.start.year)}'
                          : event.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (event.isMultiDay)
                      Text(
                        _rangeLabel(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    if (event.isRunning(DateTime.now()))
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: RunningBadge(),
                      ),
                    if (hasLocation)
                      Text(
                        '📍 ${event.location}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (event.isRecurring)
                Icon(
                  Icons.repeat,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kompakte, transparente Darstellung für bereits beendete Termine.
  Widget _buildPassed(BuildContext context, ThemeData theme, Color color) {
    final timeLabel = event.allDay
        ? 'ganztags'
        : DateFormat('HH:mm').format(event.start);
    return Opacity(
      opacity: 0.5,
      child: InkWell(
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(
                  timeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Container(
                width: 3,
                height: 16,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Text(
                  event.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (event.isRecurring)
                Icon(
                  Icons.repeat,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeBlock(ThemeData theme, Color color) {
    if (event.allDay) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event, size: 20, color: color),
          const SizedBox(height: 2),
          Text(
            'ganztags',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }
    // Mehrtägiger Termin mit Uhrzeit: je nach Tag „ab …" / „bis …" / „läuft".
    if (event.isMultiDay) {
      final muted = theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      );
      final strong = theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      );
      if (event.isFirstDay(day)) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ab', style: muted),
            Text(DateFormat('HH:mm').format(event.start), style: strong),
          ],
        );
      }
      if (event.isLastDay(day) && event.end != null) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('bis', style: muted),
            Text(DateFormat('HH:mm').format(event.end!), style: strong),
          ],
        );
      }
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.more_horiz, size: 20, color: color),
          const SizedBox(height: 2),
          Text('läuft', style: muted),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('HH:mm').format(event.start),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (event.end != null)
          Text(
            DateFormat('HH:mm').format(event.end!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
            Icon(
              Icons.cloud_off_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Nicht verbunden', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Verbinde unter „Einstellungen → Familie" deine Nextcloud, '
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
