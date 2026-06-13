import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/caldav/caldav_exception.dart';
import '../../shared/widgets/conflict_dialog.dart';
import 'task_item.dart';
import 'task_providers.dart';

/// Öffnet den Aufgaben-Editor zum Anlegen ([existing] == null) oder Bearbeiten.
Future<void> showTaskEditor(
  BuildContext context, {
  required List<TaskList> lists,
  TaskItem? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      // Über der Tastatur halten.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: _TaskEditorSheet(lists: lists, existing: existing),
    ),
  );
}

class _TaskEditorSheet extends ConsumerStatefulWidget {
  const _TaskEditorSheet({required this.lists, this.existing});
  final List<TaskList> lists;
  final TaskItem? existing;

  @override
  ConsumerState<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<_TaskEditorSheet> {
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _descCtrl;
  DateTime? _due;
  late String _listHref;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _summaryCtrl = TextEditingController(text: e?.summary ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _due = e?.due;
    _listHref = widget.lists.isNotEmpty ? widget.lists.first.href : '';
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final summary = _summaryCtrl.text.trim();
    if (summary.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Titel eingeben.')),
      );
      return;
    }
    final notifier = ref.read(tasksControllerProvider.notifier);
    final desc = _descCtrl.text.trim();

    Future<bool> write(bool force) async {
      try {
        if (_isEdit) {
          await notifier.updateTask(
            widget.existing!,
            summary: summary,
            due: _due,
            clearDue: _due == null,
            description: desc,
            force: force,
          );
        } else {
          await notifier.createTask(
            listHref: _listHref,
            summary: summary,
            due: _due,
            description: desc,
          );
        }
        return true;
      } on CalDavException catch (e) {
        if (e.isConflict && mounted) {
          final choice = await showConflictDialog(context);
          if (choice == ConflictChoice.keepMine) return write(true);
          if (choice == ConflictChoice.loadServer) {
            ref.invalidate(tasksControllerProvider);
            return true;
          }
          return false;
        }
        if (mounted) _snack('Speichern fehlgeschlagen: $e');
        return false;
      } catch (e) {
        if (mounted) _snack('Speichern fehlgeschlagen: $e');
        return false;
      }
    }

    setState(() => _busy = true);
    final ok = await write(false);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufgabe löschen?'),
        content: Text('„${widget.existing!.summary}" wird in der Nextcloud '
            'gelöscht.'),
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
    if (ok != true) return;
    final notifier = ref.read(tasksControllerProvider.notifier);

    Future<bool> runDelete(bool force) async {
      try {
        await notifier.deleteTask(widget.existing!, force: force);
        return true;
      } on CalDavException catch (e) {
        if (e.isConflict && mounted) {
          final choice = await showConflictDialog(context);
          if (choice == ConflictChoice.keepMine) return runDelete(true);
          if (choice == ConflictChoice.loadServer) {
            ref.invalidate(tasksControllerProvider);
            return true;
          }
          return false;
        }
        if (mounted) _snack('Löschen fehlgeschlagen: $e');
        return false;
      } catch (e) {
        if (mounted) _snack('Löschen fehlgeschlagen: $e');
        return false;
      }
    }

    setState(() => _busy = true);
    final done = await runDelete(false);
    if (!mounted) return;
    if (done) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showListPicker = !_isEdit && widget.lists.length > 1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEdit ? 'Aufgabe bearbeiten' : 'Neue Aufgabe',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _summaryCtrl,
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Titel',
                prefixIcon: Icon(Icons.task_alt),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Notiz (optional)',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (showListPicker) ...[
              DropdownButtonFormField<String>(
                initialValue: _listHref,
                decoration: const InputDecoration(
                  labelText: 'Liste',
                  prefixIcon: Icon(Icons.list_alt),
                  border: OutlineInputBorder(),
                ),
                items: widget.lists
                    .map((l) => DropdownMenuItem(
                          value: l.href,
                          child: Text(l.name),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _listHref = v ?? _listHref),
              ),
              const SizedBox(height: 12),
            ],
            // Fälligkeit
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon(Icons.event),
                title: Text(_due == null
                    ? 'Keine Fälligkeit'
                    : 'Fällig: ${DateFormat('d. MMM y', 'de_DE').format(_due!)}'),
                trailing: _due == null
                    ? TextButton(onPressed: _pickDue, child: const Text('Datum'))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: _pickDue,
                          ),
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _due = null),
                          ),
                        ],
                      ),
                onTap: _pickDue,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_isEdit)
                  IconButton(
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Löschen',
                    color: theme.colorScheme.error,
                  ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_busy ? 'Speichern…' : 'Speichern'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
