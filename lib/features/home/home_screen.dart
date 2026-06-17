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
    final homeEvents = filterHomeEvents(events, memberSettings);
    final upcoming = _upcoming(homeEvents, now, today);
    final countdowns = countdownEvents(events, memberSettings, today);

    // Tippen auf einen Termin/Countdown → in die Kalender-Tagesansicht springen.
    void openInCalendar(CalendarEvent e) {
      ref.read(calendarJumpProvider.notifier).set(e.start);
      context.go('/calendar');
    }

    // Tippen auf einen Tag der 2-Wochen-Übersicht → Kalender-Tagesansicht.
    void openDay(DateTime day) {
      ref
          .read(calendarJumpProvider.notifier)
          .set(DateTime(day.year, day.month, day.day, 8));
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
                  _Greeting(account: account),
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
                    const _SectionLabel('Nächste 2 Wochen'),
                    _TwoWeekCalendar(
                      today: today,
                      events: homeEvents,
                      onTapDay: openDay,
                    ),
                    const _SectionLabel('Anstehende Termine'),
                    if (upcoming.isEmpty)
                      const _EmptyHint('Keine Termine heute oder morgen 🎉')
                    else
                      SizedBox(
                        height: 150,
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

  /// Nur Termine von heute und (maximal) morgen.
  List<CalendarEvent> _upcoming(
      List<CalendarEvent> events, DateTime now, DateTime today) {
    final tomorrow = today.add(const Duration(days: 1));
    final endExclusive = today.add(const Duration(days: 2));
    final list = events.where((e) {
      if (e.allDay) {
        return !e.endDayInclusive.isBefore(today) &&
            !e.startDay.isAfter(tomorrow);
      }
      // Bereits beendete Termine ausblenden; laufende und kommende (bis morgen)
      // anzeigen.
      return !e.hasPassed(now) && e.start.isBefore(endExclusive);
    }).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list.take(12).toList();
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          _NextcloudAvatar(account: account, radius: 22),
          const Spacer(),
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
                padding: const EdgeInsets.all(10),
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
        '${DateFormat('EEEE, d. MMMM', 'de_DE').format(_now)} · '
        '${DateFormat('HH:mm').format(_now)} Uhr';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_greeting()}$who',
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface)),
          const SizedBox(height: 2),
          Text(dateLine,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Text(text,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface)),
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
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(22),
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
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: scheme.onSurface)),
              if (soon != null) ...[
                const SizedBox(height: 4),
                Text(soon,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary)),
              ] else if (event.location != null &&
                  event.location!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('📍 ${event.location}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onSurfaceVariant)),
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
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: highlighted
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant)),
                        const SizedBox(height: 1),
                        if (event.allDay)
                          Text('Ganztägig',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface))
                        else
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                DateFormat('HH:mm').format(event.start),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurface),
                              ),
                              if (event.end != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    '– ${DateFormat('HH:mm').format(event.end!)}',
                                    style: TextStyle(
                                        fontSize: 16,
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
                  const SizedBox(width: 8),
                  _Avatar(name: event.calendarName, color: color, radius: 14),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: () => context.go(_isShopping ? '/shopping' : '/tasks'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: _softShadow(context),
          ),
          child: Row(
            children: [
              _IconChip(
                  icon: _isShopping ? Icons.shopping_cart : Icons.checklist,
                  color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(list.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text('$done/$total erledigt',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: _softShadow(context),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: days <= 1
                      ? Text(days == 0 ? 'Heute' : 'Morgen',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: color))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$days',
                                style: TextStyle(
                                    fontSize: 18,
                                    height: 1,
                                    fontWeight: FontWeight.w800,
                                    color: color)),
                            Text('Tage',
                                style: TextStyle(fontSize: 9, color: color)),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                        days <= 1
                            ? dateStr
                            : 'Noch $days Tage · $dateStr',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
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
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: c, size: 22),
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
class _NextcloudAvatar extends ConsumerWidget {
  const _NextcloudAvatar({required this.account, this.radius = 22});
  final NextcloudAccount? account;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = account;
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

    final status = ref.watch(syncStatusProvider);
    final dot = radius * 0.5;

    // Tippen auf den Avatar/Statuspunkt stößt eine Synchronisation an.
    void triggerSync() {
      if (status == SyncStatus.syncing) return; // läuft bereits
      ref.invalidate(eventsControllerProvider);
      ref.invalidate(tasksControllerProvider);
      ref.invalidate(pendingSyncCountProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Synchronisiere mit der Nextcloud…'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: triggerSync,
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
                  color: _statusColor(context, status),
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

  Color _statusColor(BuildContext context, SyncStatus status) {
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
