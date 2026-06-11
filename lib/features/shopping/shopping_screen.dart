import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/account_providers.dart';
import '../tasks/task_item.dart';
import '../tasks/task_providers.dart';

/// Einkaufsliste – nutzt dieselbe VTODO/Aufgaben-Mechanik wie der Aufgaben-Tab,
/// nur mit einkaufs-optimierter Oberfläche. Der Nutzer wählt, welche
/// Aufgaben-Liste seine Einkaufsliste ist.
class ShoppingScreen extends ConsumerStatefulWidget {
  const ShoppingScreen({super.key});

  @override
  ConsumerState<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends ConsumerState<ShoppingScreen> {
  static const _prefKey = 'shopping_list_href';

  final _addCtrl = TextEditingController();
  String? _selectedHref;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _loadPref();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPref() async {
    final prefs = await SharedPreferences.getInstance();
    final href = prefs.getString(_prefKey);
    if (href != null && mounted) setState(() => _selectedHref = href);
  }

  Future<void> _savePref(String href) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, href);
  }

  /// Effektive Einkaufsliste: gespeicherte Wahl, sonst eine Liste namens
  /// „Einkauf"/„Shopping", sonst die erste.
  TaskList? _resolveList(List<TaskList> lists) {
    if (lists.isEmpty) return null;
    if (_selectedHref != null) {
      for (final l in lists) {
        if (l.href == _selectedHref) return l;
      }
    }
    for (final l in lists) {
      final n = l.name.toLowerCase();
      if (n.contains('einkauf') || n.contains('shopping') || n.contains('einkaufs')) {
        return l;
      }
    }
    return lists.first;
  }

  Future<void> _addItem(String listHref) async {
    final text = _addCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _adding = true);
    try {
      await ref
          .read(tasksControllerProvider.notifier)
          .createTask(listHref: listHref, summary: text);
      _addCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hinzufügen fehlgeschlagen: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _toggle(TaskItem item) async {
    try {
      await ref.read(tasksControllerProvider.notifier).toggle(item);
    } catch (e) {
      _snack('Konnte nicht speichern: $e');
    }
  }

  Future<void> _delete(TaskItem item) async {
    try {
      await ref.read(tasksControllerProvider.notifier).deleteTask(item);
    } catch (e) {
      _snack('Löschen fehlgeschlagen: $e');
    }
  }

  Future<void> _clearCompleted(String listHref) async {
    try {
      await ref.read(tasksControllerProvider.notifier).clearCompleted(listHref);
    } catch (e) {
      _snack('Entfernen fehlgeschlagen: $e');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(accountProvider);
    final tasksAsync = ref.watch(tasksControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einkauf'),
        actions: [
          IconButton(
            tooltip: 'Aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(tasksControllerProvider),
          ),
        ],
      ),
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
              if (lists.isEmpty) return const _NoLists();
              final list = _resolveList(lists)!;
              return _ShoppingBody(
                lists: lists,
                list: list,
                addController: _addCtrl,
                adding: _adding,
                onSelectList: (href) {
                  setState(() => _selectedHref = href);
                  _savePref(href);
                },
                onAdd: () => _addItem(list.href),
                onToggle: _toggle,
                onDelete: _delete,
                onClearCompleted: () => _clearCompleted(list.href),
              );
            },
          );
        },
      ),
    );
  }
}

class _ShoppingBody extends StatelessWidget {
  const _ShoppingBody({
    required this.lists,
    required this.list,
    required this.addController,
    required this.adding,
    required this.onSelectList,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
    required this.onClearCompleted,
  });

  final List<TaskList> lists;
  final TaskList list;
  final TextEditingController addController;
  final bool adding;
  final ValueChanged<String> onSelectList;
  final VoidCallback onAdd;
  final ValueChanged<TaskItem> onToggle;
  final ValueChanged<TaskItem> onDelete;
  final VoidCallback onClearCompleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = list.items.where((t) => !t.completed).toList();
    final done = list.items.where((t) => t.completed).toList();

    return Column(
      children: [
        // Listen-Auswahl (nur wenn es mehrere Listen gibt).
        if (lists.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DropdownButtonFormField<String>(
              initialValue: list.href,
              decoration: const InputDecoration(
                labelText: 'Einkaufsliste',
                prefixIcon: Icon(Icons.list_alt),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: lists
                  .map((l) => DropdownMenuItem(
                        value: l.href,
                        child: Text(l.name),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onSelectList(v);
              },
            ),
          ),
        // Schnell hinzufügen.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: addController,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onAdd(),
                  decoration: const InputDecoration(
                    hintText: 'Artikel hinzufügen…',
                    prefixIcon: Icon(Icons.add_shopping_cart),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: adding ? null : onAdd,
                icon: adding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: (open.isEmpty && done.isEmpty)
              ? const _EmptyList()
              : ListView(
                  children: [
                    for (final item in open)
                      _ShoppingTile(
                        item: item,
                        onToggle: () => onToggle(item),
                        onDelete: () => onDelete(item),
                      ),
                    if (done.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Im Wagen (${done.length})',
                                style: theme.textTheme.titleSmall),
                            TextButton.icon(
                              onPressed: onClearCompleted,
                              icon: const Icon(Icons.delete_sweep, size: 18),
                              label: const Text('Entfernen'),
                            ),
                          ],
                        ),
                      ),
                      for (final item in done)
                        _ShoppingTile(
                          item: item,
                          onToggle: () => onToggle(item),
                          onDelete: () => onDelete(item),
                        ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ShoppingTile extends StatelessWidget {
  const _ShoppingTile({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });
  final TaskItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey('${item.objectHref}#${item.uid}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        color: theme.colorScheme.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete, color: theme.colorScheme.onErrorContainer),
      ),
      child: CheckboxListTile(
        value: item.completed,
        onChanged: (_) => onToggle(),
        controlAffinity: ListTileControlAffinity.leading,
        shape: const Border(),
        title: Text(
          item.summary,
          style: item.completed
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: (item.description != null && item.description!.isNotEmpty)
            ? Text(item.description!)
            : null,
      ),
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        const SizedBox(height: 100),
        Icon(Icons.shopping_cart_outlined,
            size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Center(
            child: Text('Liste ist leer', style: theme.textTheme.titleLarge)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Füge oben Artikel hinzu. Hake sie beim Einkaufen ab und entferne '
            'die erledigten danach.',
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

class _NoLists extends StatelessWidget {
  const _NoLists();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Keine Liste vorhanden', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Lege in der Nextcloud-Tasks-App eine Liste an (z.B. „Einkauf"). '
              'Sie erscheint dann hier zur Auswahl.',
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
              'um die Einkaufsliste zu nutzen.',
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
