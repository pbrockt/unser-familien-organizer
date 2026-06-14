import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/blob_background.dart';
import '../calendar/calendar_event.dart';
import '../calendar/event_editor_sheet.dart';
import '../calendar/event_providers.dart';
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
    final upcoming = _upcoming(filterHomeEvents(events, memberSettings), now, today);
    final countdowns = countdownEvents(events, memberSettings, today);

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
                  _Greeting(account: account, now: now),
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
                            onTap: () =>
                                showEventEditor(context, existing: upcoming[i]),
                          ),
                        ),
                      ),
                    if (countdowns.isNotEmpty) ...[
                      const _SectionLabel('Countdown'),
                      ...countdowns.take(15).map((e) => _CountdownCard(
                            event: e,
                            today: today,
                            onTap: () =>
                                showEventEditor(context, existing: e),
                          )),
                    ],
                    const _SectionLabel('Listen'),
                    if (taskLists.isEmpty)
                      const _EmptyHint('Noch keine Listen vorhanden')
                    else
                      ...taskLists.map((l) => _ListCard(list: l)),
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
    final name = account?.username;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          _Avatar(name: name ?? '?', color: AppTheme.orange, radius: 22),
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

class _Greeting extends StatelessWidget {
  const _Greeting({required this.account, required this.now});
  final NextcloudAccount? account;
  final DateTime now;

  String _greeting() {
    final h = now.hour;
    if (h < 11) return 'Guten Morgen';
    if (h < 17) return 'Hallo';
    return 'Guten Abend';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = account?.username;
    final who = (name == null || name.isEmpty)
        ? ''
        : ', ${name[0].toUpperCase()}${name.substring(1)}';
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
          Text('Hier ist euer Familien-Überblick',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
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

// ---------- Termin-Karte (horizontal) ----------

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.now,
    required this.highlighted,
    required this.onTap,
  });
  final CalendarEvent event;
  final DateTime now;
  final bool highlighted;
  final VoidCallback onTap;

  String _dayLabel() {
    final day = DateTime(event.start.year, event.start.month, event.start.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Morgen';
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
    final color = event.color ?? AppTheme.orange;
    final soon = _soon();
    return Padding(
      padding: const EdgeInsets.only(right: 12, top: 2, bottom: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(22),
            boxShadow: _softShadow(context),
            border: highlighted
                ? Border.all(color: AppTheme.orange, width: 1.6)
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
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.orange)),
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
                                    ? AppTheme.orange
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
    final color = list.color ?? AppTheme.orange;
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
    final color = event.color ?? AppTheme.orange;
    final days = event.startDay.difference(today).inDays;
    final dateStr = DateFormat('EEE, d. MMM', 'de_DE').format(event.start);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
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
    final c = color ?? AppTheme.orange;
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
              'Verbinde im Tab „Familie" deine Nextcloud, damit hier eure '
              'Termine und Listen erscheinen.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => context.go('/family'),
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Verbinden'),
            ),
          ],
        ),
      ),
    );
  }
}
