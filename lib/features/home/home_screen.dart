import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../core/sync/sync_status.dart';
import '../../shared/widgets/blob_background.dart';
import '../calendar/calendar_event.dart';
import '../calendar/calendar_presets.dart';
import '../calendar/event_editor_sheet.dart';
import '../calendar/event_providers.dart';
import '../family/family_screen.dart';
import '../members/member_settings.dart';
import '../settings/settings_screen.dart';
import '../tasks/task_item.dart';
import '../tasks/task_providers.dart';
import 'dashboard_providers.dart';

List<BoxShadow> _softShadow(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return [
    BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];
}

/// Startseite als „Familien-Snapshot". Passt sich Hell/Dunkel an.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    final events = ref.watch(visibleEventsProvider);
    final memberSettings = ref.watch(memberSettingsProvider).value ?? const {};
    final taskLists = ref.watch(tasksControllerProvider).value ?? const [];
    final pendingSync = ref.watch(pendingSyncCountProvider).value ?? 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final upcomingDays = ref.watch(upcomingDaysProvider).value ?? 2;
    final presets = ref.watch(calendarPresetsProvider).value ?? const [];
    final selectedFilter = ref.watch(homeCalendarFilterProvider).value;

    // Startseiten-Termine: standardmäßig alle sichtbaren Kalender, optional auf
    // ein gewähltes Filter-Preset eingeschränkt (der Filter ersetzt die frühere
    // „Anstehende Termine"-Kalenderauswahl in den Einstellungen).
    var homeEvents = events;
    if (selectedFilter != null) {
      CalendarPreset? preset;
      for (final p in presets) {
        if (p.name == selectedFilter) {
          preset = p;
          break;
        }
      }
      if (preset != null) {
        final visible = preset.visibleHrefs;
        homeEvents =
            homeEvents.where((e) => visible.contains(e.calendarHref)).toList();
      }
    }
    final upcoming = _upcoming(homeEvents, now, today, upcomingDays);
    final countdowns = countdownEvents(events, memberSettings, today);

    // Tippen auf einen Termin/Countdown → in die Kalender-Tagesansicht springen.
    void openInCalendar(CalendarEvent e) {
      ref.read(calendarJumpProvider.notifier).set(CalendarJumpTarget(e.start));
      context.go('/calendar');
    }

    // Tippen auf die 2-Wochen-Übersicht → Kalender-Tab (Monatsansicht), nicht
    // in die Tagesansicht.
    void openDay(DateTime day) {
      ref.read(calendarJumpProvider.notifier).set(
            CalendarJumpTarget(DateTime(day.year, day.month, day.day),
                openDay: false),
          );
      context.go('/calendar');
    }

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: BlobBackground()),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(eventsControllerProvider);
                ref.invalidate(tasksControllerProvider);
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  _TopBar(account: account),
                  if (pendingSync > 0)
                    _SyncBanner(
                      count: pendingSync,
                      onSync: () {
                        ref.invalidate(eventsControllerProvider);
                        ref.invalidate(tasksControllerProvider);
                        ref.invalidate(pendingSyncCountProvider);
                      },
                    ),
                  if (account == null)
                    const _ConnectCard()
                  else ...[
                    _SectionLabel(
                      'Nächste 2 Wochen',
                      trailing: presets.isEmpty
                          ? null
                          : _HomeFilterButton(
                              presets: presets,
                              selected: selectedFilter,
                              onSelected: (name) => ref
                                  .read(homeCalendarFilterProvider.notifier)
                                  .set(name),
                            ),
                    ),
                    _TwoWeekCalendar(
                      today: today,
                      events: homeEvents,
                      onTapDay: openDay,
                    ),
                    const _SectionLabel('Anstehende Termine'),
                    if (upcoming.isEmpty)
                      const _EmptyHint('Keine anstehenden Termine 🎉')
                    else
                      SizedBox(
                        height: 118,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: upcoming.length,
                          itemBuilder: (context, i) => _EventCard(
                            event: upcoming[i],
                            now: now,
                            highlighted: i == 0,
                            onTap: () => openInCalendar(upcoming[i]),
                            onLongPress: () =>
                                showEventEditor(context, existing: upcoming[i]),
                          ),
                        ),
                      ),
                    const _SectionLabel('Überblick'),
                    ...countdowns.map((e) => _CountdownCard(
                          event: e,
                          today: today,
                          onTap: () => openInCalendar(e),
                        )),
                    ...taskLists.map((l) => _ListCard(list: l)),
                    if (countdowns.isEmpty && taskLists.isEmpty)
                      const _EmptyHint('Noch keine Listen vorhanden'),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Anstehende Termine der nächsten [days] Tage (1 = nur heute).
  List<CalendarEvent> _upcoming(
      List<CalendarEvent> events, DateTime now, DateTime today, int days) {
    final lastDay = today.add(Duration(days: days - 1));
    final endExclusive = today.add(Duration(days: days));
    final list = events.where((e) {
      if (e.allDay) {
        return !e.endDayInclusive.isBefore(today) &&
            !e.startDay.isAfter(lastDay);
      }
      // Bereits beendete Termine ausblenden; laufende und kommende anzeigen.
      return !e.hasPassed(now) && e.start.isBefore(endExclusive);
    }).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list.take(20).toList();
  }
}

// ---------- Kopfbereich ----------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.account});
  final NextcloudAccount? account;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          _NextcloudAvatar(account: account, radius: 24),
          const SizedBox(width: 12),
          // Begrüßung + Datum/Uhrzeit direkt neben dem Avatar (spart Platz).
          Expanded(child: _Greeting(account: account)),
          const SizedBox(width: 8),
          Material(
            color: Theme.of(context).cardColor,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: Colors.black26,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Icon(Icons.settings_outlined, color: scheme.onSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Greeting extends StatefulWidget {
  const _Greeting({required this.account});
  final NextcloudAccount? account;

  @override
  State<_Greeting> createState() => _GreetingState();
}

class _GreetingState extends State<_Greeting> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Uhrzeit jede halbe Minute aktualisieren.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _greeting() {
    final h = _now.hour;
    if (h < 11) return 'Guten Morgen';
    if (h < 17) return 'Hallo';
    return 'Guten Abend';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.account?.username;
    final who = (name == null || name.isEmpty)
        ? ''
        : ', ${name[0].toUpperCase()}${name.substring(1)}';
    final dateLine =
        '${DateFormat('EEE, d. MMM', 'de_DE').format(_now)} · '
        '${DateFormat('HH:mm').format(_now)} Uhr';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${_greeting()}$who',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface)),
        const SizedBox(height: 1),
        Text(dateLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.primary)),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 22, trailing == null ? 20 : 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Filter-Auswahl für die Startseite: „Alle" + gespeicherte Presets.
class _HomeFilterButton extends StatelessWidget {
  const _HomeFilterButton({
    required this.presets,
    required this.selected,
    required this.onSelected,
  });
  final List<CalendarPreset> presets;
  final String? selected;
  final void Function(String? name) onSelected;

  // Platzhalter-Wert für „Alle". PopupMenuButton löst bei einem `null`-Wert
  // `onSelected` NICHT aus (null gilt als „abgebrochen") – sonst ließe sich
  // „Alle" nie wieder auswählen.
  static const _allValue = ' __alle__';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = selected ?? 'Alle';
    return PopupMenuButton<String>(
      tooltip: 'Filter',
      onSelected: (v) => onSelected(v == _allValue ? null : v),
      itemBuilder: (ctx) => [
        CheckedPopupMenuItem<String>(
          value: _allValue,
          checked: selected == null,
          child: const Text('Alle'),
        ),
        for (final p in presets)
          CheckedPopupMenuItem<String>(
            value: p.name,
            checked: selected == p.name,
            child: Text(p.name),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface)),
            Icon(Icons.arrow_drop_down,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ---------- 2-Wochen-Kalenderübersicht ----------

/// Kompakte 2-Wochen-Übersicht (aktuelle + nächste Woche) auf der Startseite.
/// Zeigt Event-Punkte je Tag; Tippen auf einen Tag öffnet die Kalender-
/// Tagesansicht für diesen Tag.
class _TwoWeekCalendar extends StatelessWidget {
  const _TwoWeekCalendar({
    required this.today,
    required this.events,
    required this.onTapDay,
  });
  final DateTime today;
  final List<CalendarEvent> events;
  final void Function(DateTime day) onTapDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Beginn bei Montag der aktuellen Woche, damit die Spalten zu den
    // Wochentagen passen.
    final start = today.subtract(Duration(days: today.weekday - 1));
    const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

    Widget cell(DateTime day) {
      final isToday = day.year == today.year &&
          day.month == today.month &&
          day.day == today.day;
      final isPast = day.isBefore(today);
      final dayEvents = events.where((e) => e.occursOn(day)).toList();
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTapDay(day),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isToday ? scheme.primary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isToday
                          ? scheme.onPrimary
                          : isPast
                              ? scheme.onSurfaceVariant.withValues(alpha: 0.5)
                              : scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final e in dayEvents.take(3))
                        Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: e.color ?? scheme.primary,
                          ),
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

    Widget weekRow(int offset) => Row(
          children: [
            for (var i = 0; i < 7; i++)
              cell(start.add(Duration(days: offset + i))),
          ],
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: _softShadow(context),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final l in labels)
                Expanded(
                  child: Center(
                    child: Text(l,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          weekRow(0),
          weekRow(7),
        ],
      ),
    );
  }
}

// ---------- Termin-Karte (horizontal) ----------

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.now,
    required this.highlighted,
    required this.onTap,
    this.onLongPress,
  });
  final CalendarEvent event;
  final DateTime now;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  String _dayLabel() {
    final day = DateTime(event.start.year, event.start.month, event.start.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    final date = DateFormat('d. MMM', 'de_DE').format(event.start);
    if (diff == 0) return 'Heute, $date';
    if (diff == 1) return 'Morgen, $date';
    return DateFormat('EEE, d. MMM', 'de_DE').format(event.start);
  }

  String? _soon() {
    if (event.allDay) return null;
    final diff = event.start.difference(now);
    if (!diff.isNegative && diff.inMinutes < 60) {
      return 'Beginnt in ${diff.inMinutes} Min';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = event.color ?? scheme.primary;
    final soon = _soon();
    return Padding(
      padding: const EdgeInsets.only(right: 12, top: 2, bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 185,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(18),
            boxShadow: _softShadow(context),
            border: highlighted
                ? Border.all(color: scheme.primary, width: 1.6)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: scheme.onSurface)),
              if (soon != null) ...[
                const SizedBox(height: 3),
                Text(soon,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary)),
              ] else if (event.location != null &&
                  event.location!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text('📍 ${event.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tages-Hinweis (Heute/Morgen/Datum) klein über der Zeit.
                        Text(_dayLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: highlighted
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant)),
                        const SizedBox(height: 1),
                        if (event.allDay)
                          Text('Ganztägig',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface))
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                DateFormat('HH:mm').format(event.start),
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurface),
                              ),
                              if (event.end != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    '– ${DateFormat('HH:mm').format(event.end!)}',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.45)),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Avatar(name: event.calendarName, color: color, radius: 12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Listen-Karte ----------

class _ListCard extends StatelessWidget {
  const _ListCard({required this.list});
  final TaskList list;

  bool get _isShopping {
    final n = list.name.toLowerCase();
    return n.contains('einkauf') || n.contains('shopping');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = list.items.length;
    final done = list.items.where((t) => t.completed).length;
    final color = list.color ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTap: () => context.go(_isShopping ? '/shopping' : '/tasks'),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _softShadow(context),
          ),
          child: Row(
            children: [
              _IconChip(
                  icon: _isShopping ? Icons.shopping_cart : Icons.checklist,
                  color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(list.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 1),
                    Text('$done/$total erledigt',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Bausteine ----------

class _CountdownCard extends StatelessWidget {
  const _CountdownCard({
    required this.event,
    required this.today,
    required this.onTap,
  });
  final CalendarEvent event;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = event.color ?? scheme.primary;
    final days = event.startDay.difference(today).inDays;
    final dateStr = DateFormat('EEE, d. MMM', 'de_DE').format(event.start);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: _softShadow(context),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Center(
                  child: days <= 1
                      ? Text(days == 0 ? 'Heute' : 'Morgen',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: color))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$days',
                                style: TextStyle(
                                    fontSize: 16,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    color: color)),
                            Text('Tage',
                                style: TextStyle(fontSize: 8, color: color)),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 1),
                    Text(
                        days <= 1
                            ? dateStr
                            : 'Noch $days Tage · $dateStr',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: c, size: 18),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.color, this.radius = 16});
  final String name;
  final Color color;
  final double radius;

  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return trimmed.length >= 2
        ? trimmed.substring(0, 2).toUpperCase()
        : trimmed.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(_initials,
          style: TextStyle(
              color: Colors.white,
              fontSize: radius * 0.7,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// Profilbild aus der Nextcloud (echtes Bild oder generierte Initialen).
/// Fällt auf lokale Initialen ([_Avatar]) zurück, wenn kein Konto/Bild da ist.
/// Zeigt zusätzlich einen kleinen Sync-Statuspunkt (grün = online, gelb =
/// synchronisiert gerade, rot = offline).
class _NextcloudAvatar extends ConsumerStatefulWidget {
  const _NextcloudAvatar({required this.account, this.radius = 22});
  final NextcloudAccount? account;
  final double radius;

  @override
  ConsumerState<_NextcloudAvatar> createState() => _NextcloudAvatarState();
}

class _NextcloudAvatarState extends ConsumerState<_NextcloudAvatar> {
  /// Frühestens alle … darf ein manueller Sync per Tipp ausgelöst werden.
  static const _cooldown = Duration(minutes: 1);

  int _taps = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _handleTap() {
    final now = DateTime.now();
    // Tap-Serie zurücksetzen, wenn zwischen den Tipps zu viel Zeit liegt.
    if (now.difference(_lastTap) > const Duration(milliseconds: 1200)) {
      _taps = 0;
    }
    _lastTap = now;
    _taps++;
    if (_taps >= 5) {
      _taps = 0;
      _showDiagnostics();
      return;
    }
    _triggerSync();
  }

  void _triggerSync({bool force = false}) {
    if (ref.read(syncStatusProvider).status == SyncStatus.syncing) return;

    final now = DateTime.now();
    final since = now.difference(_lastSyncAt);
    if (!force && since < _cooldown) {
      // Sperre aktiv – nur beim ersten Tipp einer Serie kurz Bescheid geben.
      if (_taps <= 1) {
        final remaining = (_cooldown - since).inSeconds + 1;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gerade erst synchronisiert – bitte noch $remaining s '
              'warten.'),
          duration: const Duration(seconds: 2),
        ));
      }
      return;
    }

    _lastSyncAt = now;
    ref.invalidate(eventsControllerProvider);
    ref.invalidate(tasksControllerProvider);
    ref.invalidate(pendingSyncCountProvider);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Synchronisiere mit der Nextcloud…'),
      duration: Duration(seconds: 2),
    ));
  }

  String _statusLabel(SyncStatus s) => switch (s) {
        SyncStatus.online => 'Online – zuletzt erfolgreich synchronisiert',
        SyncStatus.syncing => 'Synchronisiert gerade …',
        SyncStatus.offline => 'Offline – Server nicht erreichbar',
        SyncStatus.idle => 'Noch nicht synchronisiert',
      };

  /// Fehler-/Diagnose-Popup (5× auf den Statuspunkt tippen).
  Future<void> _showDiagnostics() async {
    final a = widget.account;
    final sync = ref.read(syncStatusProvider);
    final pending = ref.read(pendingSyncCountProvider).value;
    final eventsAsync = ref.read(eventsControllerProvider);
    final eventsInfo = eventsAsync.hasError
        ? 'Fehler: ${eventsAsync.error}'
        : '${eventsAsync.value?.length ?? 0} Termine geladen';
    String fmt(DateTime? d) =>
        d == null ? '—' : DateFormat('d. MMM y, HH:mm:ss', 'de_DE').format(d);

    final lines = <String>[
      'Verbindung: ${a == null ? 'NICHT verbunden ⚠️' : 'verbunden'}',
      if (a != null) 'Benutzer: ${a.username}',
      if (a != null) 'Server: ${a.baseUrl}',
      'Status: ${_statusLabel(sync.status)}',
      'Letzter Versuch: ${fmt(sync.lastAttemptAt)}',
      'Letzter erfolgreicher Sync: ${fmt(sync.lastSuccessAt)}',
      'Termine: $eventsInfo',
      'Offene Offline-Änderungen: ${pending ?? '—'}',
      '\n— Details —',
      sync.debugInfo ?? 'Noch kein Sync-Bericht vorhanden.',
      if (sync.lastError != null) '\n⚠️ Letzter Fehler:\n${sync.lastError}',
    ];

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔍 Sync-Diagnose'),
        content: SingleChildScrollView(
          child: SelectableText(lines.join('\n')),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _triggerSync(force: true);
            },
            child: const Text('Jetzt synchronisieren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  Color _statusColor(SyncStatus status) {
    switch (status) {
      case SyncStatus.online:
        return const Color(0xFF34C759); // grün – erreichbar/synchronisiert
      case SyncStatus.syncing:
        return const Color(0xFFFFB300); // gelb – synchronisiert gerade
      case SyncStatus.offline:
        return const Color(0xFFE53935); // rot – offline
      case SyncStatus.idle:
        return Theme.of(context).colorScheme.onSurfaceVariant; // grau
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final radius = widget.radius;
    final fallback = _Avatar(
      name: a?.username ?? '?',
      color: Theme.of(context).colorScheme.primary,
      radius: radius,
    );

    final Widget avatar;
    if (a == null) {
      avatar = fallback;
    } else {
      final url = '${a.baseUrl}/index.php/avatar/${a.username}/128';
      final auth = 'Basic ${base64Encode(utf8.encode(a.credentials))}';
      avatar = ClipOval(
        child: Image.network(
          url,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          headers: {'Authorization': auth},
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback,
        ),
      );
    }

    // Ohne Konto kein Statuspunkt.
    if (a == null) return avatar;

    final status = ref.watch(syncStatusProvider).status;
    final dot = radius * 0.5;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: Stack(
          children: [
            avatar,
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: _statusColor(status),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.count, required this.onSync});
  final int count;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_sync_outlined, color: scheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                count == 1
                    ? '1 Änderung wartet auf Sync'
                    : '$count Änderungen warten auf Sync',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
            TextButton(onPressed: onSync, child: const Text('Sync')),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(text,
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: _softShadow(context),
        ),
        child: Column(
          children: [
            const _IconChip(icon: Icons.cloud_off_outlined),
            const SizedBox(height: 12),
            Text('Noch nicht verbunden',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 6),
            Text(
              'Verbinde deine Nextcloud, damit hier eure Termine und Listen '
              'erscheinen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FamilyScreen()),
              ),
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Verbinden'),
            ),
          ],
        ),
      ),
    );
  }
}
