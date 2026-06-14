import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/caldav/caldav_exception.dart';
import '../../shared/widgets/conflict_dialog.dart';
import '../../shared/widgets/countdown_confirm_dialog.dart';
import 'calendar_event.dart';
import 'event_editor_sheet.dart';
import 'event_providers.dart';

/// Aktionen-Menü für einen Termin (per Long-Press): Bearbeiten, Teilen, Löschen.
Future<void> showEventActions(
  BuildContext context,
  WidgetRef ref,
  CalendarEvent event,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Bearbeiten'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Teilen'),
            onTap: () => Navigator.pop(ctx, 'share'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Löschen'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == 'edit') {
    await showEventEditor(context, existing: event);
  } else if (action == 'share') {
    await _shareEvent(context, event);
  } else if (action == 'delete') {
    await _deleteEvent(context, ref, event);
  }
}

Future<void> _shareEvent(BuildContext context, CalendarEvent e) async {
  final df = DateFormat('EEEE, d. MMMM y', 'de_DE');
  final tf = DateFormat('HH:mm');
  final when = e.allDay
      ? df.format(e.start)
      : '${df.format(e.start)}, ${tf.format(e.start)}'
          '${e.end != null ? ' – ${tf.format(e.end!)}' : ''} Uhr';
  final loc = (e.location != null && e.location!.isNotEmpty)
      ? '\n📍 ${e.location}'
      : '';
  final text = '${e.summary}\n$when$loc';
  try {
    await SharePlus.instance
        .share(ShareParams(text: text, subject: e.summary));
  } catch (err) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Teilen nicht möglich: $err')),
      );
    }
  }
}

Future<void> _deleteEvent(
    BuildContext context, WidgetRef ref, CalendarEvent ev) async {
  final isSeriesInstance = ev.isRecurring && ev.recurrenceDate != null;
  var deleteOnlyThis = false;
  if (isSeriesInstance) {
    final scope = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Serientermin löschen'),
        content: const Text(
            'Möchtest du nur diesen einen Termin oder die ganze Serie löschen?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'series'),
              child: const Text('Ganze Serie')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'this'),
              child: const Text('Nur diesen')),
        ],
      ),
    );
    if (scope == null || scope == 'cancel') return;
    deleteOnlyThis = scope == 'this';
  }
  if (!context.mounted) return;

  final dateLabel = DateFormat('d. MMM y', 'de_DE').format(ev.start);
  final ok = await showCountdownDeleteDialog(
    context,
    title: deleteOnlyThis
        ? 'Diesen Termin löschen?'
        : isSeriesInstance
            ? 'Ganze Serie löschen?'
            : 'Termin löschen?',
    message: deleteOnlyThis
        ? '„${ev.summary}" am $dateLabel wird aus der Serie entfernt.'
        : isSeriesInstance
            ? '„${ev.summary}" – die gesamte Serie wird gelöscht. Diese Aktion '
                'kann nicht rückgängig gemacht werden.'
            : '„${ev.summary}" wird endgültig aus der Nextcloud gelöscht.',
  );
  if (!ok) return;

  final notifier = ref.read(eventsControllerProvider.notifier);
  Future<bool> run(bool force) async {
    try {
      if (deleteOnlyThis) {
        await notifier.deleteOccurrence(ev, force: force);
      } else {
        await notifier.deleteEvent(ev, force: force);
      }
      return true;
    } on CalDavException catch (e) {
      if (e.isConflict && context.mounted) {
        final choice = await showConflictDialog(context);
        if (choice == ConflictChoice.keepMine) return run(true);
        if (choice == ConflictChoice.loadServer) {
          ref.invalidate(eventsControllerProvider);
          return true;
        }
        return false;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Löschen fehlgeschlagen: $e')),
        );
      }
      return false;
    }
  }

  await run(false);
}
