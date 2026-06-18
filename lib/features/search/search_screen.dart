import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../calendar/birthdays.dart';
import '../calendar/calendar_event.dart';
import '../calendar/event_providers.dart';
import '../tasks/task_item.dart';
import '../tasks/task_providers.dart';

/// Volltextsuche über Termine und Aufgaben (Titel/Ort/Beschreibung).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _eventWhen(CalendarEvent e) {
    if (isBirthday(e)) return DateFormat('d. MMM', 'de_DE').format(e.start);
    if (e.allDay) {
      return '${DateFormat('EEE, d. MMM', 'de_DE').format(e.start)} · Ganztägig';
    }
    return DateFormat('EEE, d. MMM · HH:mm', 'de_DE').format(e.start);
  }

  void _openEvent(CalendarEvent e) {
    final router = GoRouter.of(context);
    ref.read(calendarJumpProvider.notifier).set(CalendarJumpTarget(e.start));
    Navigator.of(context).pop();
    router.go('/calendar');
  }

  void _openTasks() {
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go('/tasks');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final events = ref.watch(visibleEventsProvider);
    final taskLists =
        ref.watch(tasksControllerProvider).value ?? const <TaskList>[];

    final eventHits = <CalendarEvent>[];
    final taskHits = <({TaskItem item, String list})>[];
    if (q.isNotEmpty) {
      final seen = <String>{};
      for (final e in events) {
        final hay = '${e.summary} ${e.location ?? ''} ${e.description ?? ''}'
            .toLowerCase();
        if (!hay.contains(q)) continue;
        // Serien-Instanzen zusammenfassen.
        if (!seen.add('${e.uid}|${e.summary}')) continue;
        eventHits.add(e);
      }
      eventHits.sort((a, b) => a.start.compareTo(b.start));
      for (final l in taskLists) {
        for (final t in l.items) {
          final hay = '${t.summary} ${t.description ?? ''}'.toLowerCase();
          if (hay.contains(q)) taskHits.add((item: t, list: l.name));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Termine & Aufgaben suchen…',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Leeren',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: q.isEmpty
          ? const _Hint('Tippe oben, um Termine & Aufgaben zu durchsuchen.')
          : (eventHits.isEmpty && taskHits.isEmpty)
          ? const _Hint('Nichts gefunden.')
          : ListView(
              children: [
                if (eventHits.isNotEmpty) _header('Termine'),
                ...eventHits.map(
                  (e) => ListTile(
                    leading: CircleAvatar(
                      radius: 7,
                      backgroundColor: e.color ?? scheme.primary,
                    ),
                    title: Text(
                      isBirthday(e) ? '🎂 ${e.summary}' : e.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_eventWhen(e)),
                    onTap: () => _openEvent(e),
                  ),
                ),
                if (taskHits.isNotEmpty) _header('Aufgaben'),
                ...taskHits.map(
                  (t) => ListTile(
                    leading: Icon(
                      t.item.completed
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: t.item.color ?? scheme.primary,
                    ),
                    title: Text(
                      t.item.summary,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.item.completed
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    subtitle: Text(
                      t.item.due != null
                          ? '${t.list} · bis ${DateFormat('d. MMM', 'de_DE').format(t.item.due!)}'
                          : t.list,
                    ),
                    onTap: _openTasks,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}
