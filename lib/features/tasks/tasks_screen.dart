import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/account_providers.dart';
import 'task_editor_sheet.dart';
import 'task_item.dart';
import 'task_providers.dart';

/// Aufgaben-Bereich (VTODO per CalDAV): Aufgabenlisten mit Abhaken.
class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountProvider);
    final tasksAsync = ref.watch(tasksControllerProvider);

    final lists = tasksAsync.value ?? const <TaskList>[];
    final canAdd = accountAsync.value != null && lists.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgaben'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(tasksControllerProvider),
          ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton(
              onPressed: () => showTaskEditor(context, lists: lists),
              tooltip: 'Neue Aufgabe',
              child: const Icon(Icons.add),
            )
          : null,
      body: accountAsync.maybeWhen(
        orElse: () => const Center(child: CircularProgressIndicator()),
        data: (account) {
          if (account == null) return const _ConnectPrompt();
          return tasksAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorView(
              message: '$e',
              onRetry: () => ref.invalidate(tasksControllerProvider),
            ),
            data: (lists) {
              final hasAny = lists.any((l) => l.items.isNotEmpty);
              if (lists.isEmpty || !hasAny) return const _EmptyTasks();
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(tasksControllerProvider);
                  await ref.read(tasksControllerProvider.future);
                },
                child: _TaskListsView(lists: lists),
              );
            },
          );
        },
      ),
    );
  }
}

class _TaskListsView extends ConsumerWidget {
  const _TaskListsView({required this.lists});
  final List<TaskList> lists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Nur Listen mit Inhalt; bei mehreren Listen Überschriften zeigen.
    final visible = lists.where((l) => l.items.isNotEmpty).toList();
    final showHeaders = visible.length > 1;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final list in visible) ...[
          if (showHeaders) _ListHeader(list: list),
          for (final item in list.items)
            _TaskTile(
              item: item,
              onToggle: () => _toggle(context, ref, item),
              onEdit: () =>
                  showTaskEditor(context, lists: lists, existing: item),
            ),
        ],
      ],
    );
  }

  Future<void> _toggle(
      BuildContext context, WidgetRef ref, TaskItem item) async {
    try {
      await ref.read(tasksControllerProvider.notifier).toggle(item);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konnte nicht speichern: $e')),
        );
      }
    }
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.list});
  final TaskList list;

  @override
  Widget build(BuildContext context) {
    final color = list.color ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(list.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Text('${list.openCount} offen',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.item,
    required this.onToggle,
    required this.onEdit,
  });
  final TaskItem item;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  String? _dueLabel() {
    final due = item.due;
    if (due == null) return null;
    return 'Fällig: ${DateFormat('d. MMM y', 'de_DE').format(due)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.color ?? theme.colorScheme.primary;
    final due = _dueLabel();
    final overdue = item.due != null &&
        !item.completed &&
        item.due!.isBefore(DateTime.now());

    return ListTile(
      leading: Checkbox(
        value: item.completed,
        activeColor: color,
        onChanged: (_) => onToggle(),
        shape: const CircleBorder(),
      ),
      title: Text(
        item.summary,
        style: item.completed
            ? theme.textTheme.bodyLarge?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              )
            : theme.textTheme.bodyLarge,
      ),
      subtitle: due == null
          ? null
          : Text(
              due,
              style: theme.textTheme.bodySmall?.copyWith(
                color: overdue
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onEdit,
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  const _EmptyTasks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.checklist_rtl,
            size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Center(
          child: Text('Keine Aufgaben', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Lege Aufgaben in der Nextcloud-Tasks-App an – sie erscheinen '
            'hier automatisch und lassen sich abhaken.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
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
              'Verbinde unter „Einstellungen → Familie" deine Nextcloud, '
              'um Aufgaben zu sehen.',
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
