import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_providers.dart';
import '../calendar/calendar_event.dart';
import '../calendar/event_editor_sheet.dart';
import '../calendar/event_providers.dart';
import '../tasks/task_editor_sheet.dart';
import '../tasks/task_item.dart';
import '../tasks/task_providers.dart';
import 'dashboard_providers.dart';

/// Startseite als Dashboard „Heute & morgen": die wichtigsten Dinge auf einen
/// Blick – heutige & morgige Termine, fällige Aufgaben, Einkauf.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider).value;
    final events = ref.watch(eventsControllerProvider).value ?? const [];
    final taskLists = ref.watch(tasksControllerProvider).value ?? const [];
    final shopping = ref.watch(shoppingSummaryProvider).value;
    final pendingSync = ref.watch(pendingSyncCountProvider).value ?? 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final todayEvents = _eventsOn(events, today);
    final tomorrowEvents = _eventsOn(events, tomorrow);
    final dueTasks = _dueTasks(taskLists, tomorrow);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(eventsControllerProvider);
          ref.invalidate(tasksControllerProvider);
        },
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _Header(date: now),
            if (account != null && pendingSync > 0)
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
              _Section(
                title: 'Heute',
                icon: Icons.wb_sunny_outlined,
                child: todayEvents.isEmpty
                    ? const _EmptyHint('Heute nichts geplant 🎉')
                    : Column(
                        children: [
                          for (final e in todayEvents)
                            _EventRow(
                              event: e,
                              onTap: () =>
                                  showEventEditor(context, existing: e),
                            ),
                        ],
                      ),
                onSeeAll: () => context.go('/calendar'),
              ),
              if (dueTasks.isNotEmpty)
                _Section(
                  title: 'Fällige Aufgaben',
                  icon: Icons.checklist,
                  onSeeAll: () => context.go('/tasks'),
                  child: Column(
                    children: [
                      for (final t in dueTasks)
                        _TaskRow(
                          task: t,
                          today: today,
                          onToggle: () => ref
                              .read(tasksControllerProvider.notifier)
                              .toggle(t),
                          onTap: () => showTaskEditor(context,
                              lists: taskLists, existing: t),
                        ),
                    ],
                  ),
                ),
              if (shopping != null && shopping.openCount > 0)
                _ShoppingCard(
                  summary: shopping,
                  onTap: () => context.go('/shopping'),
                ),
              _Section(
                title: 'Morgen',
                icon: Icons.wb_twilight,
                onSeeAll: () => context.go('/calendar'),
                child: tomorrowEvents.isEmpty
                    ? const _EmptyHint('Morgen nichts geplant')
                    : Column(
                        children: [
                          for (final e in tomorrowEvents)
                            _EventRow(
                              event: e,
                              onTap: () =>
                                  showEventEditor(context, existing: e),
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  List<CalendarEvent> _eventsOn(List<CalendarEvent> events, DateTime day) {
    final list = events.where((e) => e.occursOn(day)).toList()
      ..sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.start.compareTo(b.start);
      });
    return list;
  }

  List<TaskItem> _dueTasks(List<TaskList> lists, DateTime tomorrow) {
    final due = <TaskItem>[];
    for (final l in lists) {
      for (final t in l.items) {
        if (t.completed || t.due == null) continue;
        if (t.due!.isBefore(tomorrow)) due.add(t); // heute fällig oder überfällig
      }
    }
    due.sort((a, b) => a.due!.compareTo(b.due!));
    return due;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.date});
  final DateTime date;

  String _greeting() {
    final h = date.hour;
    if (h < 11) return 'Guten Morgen';
    if (h < 17) return 'Hallo';
    return 'Guten Abend';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateLabel = DateFormat('EEEE, d. MMMM', 'de_DE').format(date);
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, MediaQuery.of(context).padding.top + 24, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, Color.alphaBlend(Colors.white24, scheme.primary)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_greeting()} 👋',
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateLabel[0].toUpperCase() + dateLabel.substring(1),
            style: TextStyle(
              color: scheme.onPrimary.withValues(alpha: 0.9),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.onSeeAll,
  });
  final String title;
  final IconData icon;
  final Widget child;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    child: const Text('Alle'),
                  ),
              ],
            ),
          ),
          Card(child: Padding(padding: const EdgeInsets.all(4), child: child)),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});
  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = event.color ?? Theme.of(context).colorScheme.primary;
    final time = event.allDay
        ? 'Ganztägig'
        : DateFormat('HH:mm').format(event.start);
    return ListTile(
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(time,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13)),
        ],
      ),
      title: Text(event.summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: (event.location != null && event.location!.isNotEmpty)
          ? Text('📍 ${event.location}',
              maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Container(width: 5, height: 36, decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(3))),
      onTap: onTap,
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.today,
    required this.onToggle,
    required this.onTap,
  });
  final TaskItem task;
  final DateTime today;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = task.due!.isBefore(today);
    final label = overdue
        ? 'Überfällig: ${DateFormat('d. MMM', 'de_DE').format(task.due!)}'
        : 'Heute fällig';
    return ListTile(
      leading: Checkbox(
        value: task.completed,
        shape: const CircleBorder(),
        onChanged: (_) => onToggle(),
      ),
      title: Text(task.summary, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(label,
          style: TextStyle(
              color: overdue ? scheme.error : scheme.onSurfaceVariant)),
      onTap: onTap,
    );
  }
}

class _ShoppingCard extends StatelessWidget {
  const _ShoppingCard({required this.summary, required this.onTap});
  final ShoppingSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Card(
        color: scheme.tertiaryContainer,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.tertiary,
            child: Icon(Icons.shopping_cart, color: scheme.onTertiary),
          ),
          title: Text(summary.listName ?? 'Einkaufsliste',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${summary.openCount} Artikel offen'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        color: scheme.secondaryContainer,
        child: ListTile(
          leading: Icon(Icons.cloud_sync_outlined,
              color: scheme.onSecondaryContainer),
          title: Text(
            count == 1
                ? '1 Änderung wartet auf Synchronisierung'
                : '$count Änderungen warten auf Synchronisierung',
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
          subtitle: Text('Offline gespeichert – tippe zum Hochladen',
              style: TextStyle(color: scheme.onSecondaryContainer)),
          trailing: FilledButton.tonal(
            onPressed: onSync,
            child: const Text('Sync'),
          ),
          onTap: onSync,
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
      padding: const EdgeInsets.all(16),
      child: Text(text,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}

class _ConnectCard extends StatelessWidget {
  const _ConnectCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(Icons.cloud_off_outlined,
                  size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('Noch nicht verbunden',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Verbinde im Tab „Familie" deine Nextcloud, damit hier deine '
                'Termine, Aufgaben und der Einkauf erscheinen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
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
      ),
    );
  }
}
