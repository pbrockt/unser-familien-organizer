import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'study_settings.dart';

/// Editor für die Lernzeiten je Wochentag (Schalter + antippbare Uhrzeiten).
/// Wird in den Einstellungen UND im Schularbeit-Formular verwendet.
class StudyWindowsEditor extends ConsumerWidget {
  const StudyWindowsEditor({super.key});

  static const _dayNames = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _editTime(
    BuildContext context,
    WidgetRef ref,
    int i,
    StudyWindow w,
  ) async {
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: w.startMinute ~/ 60,
        minute: w.startMinute % 60,
      ),
      helpText: 'Lernen ab',
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: w.endMinute ~/ 60, minute: w.endMinute % 60),
      helpText: 'Lernen bis',
    );
    if (end == null) return;
    final s = start.hour * 60 + start.minute;
    final e = end.hour * 60 + end.minute;
    await ref
        .read(studyWindowsProvider.notifier)
        .setDay(
          i,
          w.copyWith(
            enabled: true,
            startMinute: s,
            endMinute: e > s ? e : s + 60,
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windows =
        ref.watch(studyWindowsProvider).value ?? defaultStudyWindows();
    return Column(
      children: [
        for (var i = 0; i < 7; i++)
          ListTile(
            title: Text(_dayNames[i]),
            subtitle: Text(
              windows[i].enabled
                  ? '${_fmt(windows[i].startMinute)}–${_fmt(windows[i].endMinute)}  ·  tippen zum Ändern'
                  : 'Kein Lernen',
            ),
            onTap: windows[i].enabled
                ? () => _editTime(context, ref, i, windows[i])
                : null,
            trailing: Switch(
              value: windows[i].enabled,
              onChanged: (v) => ref
                  .read(studyWindowsProvider.notifier)
                  .setDay(i, windows[i].copyWith(enabled: v)),
            ),
          ),
      ],
    );
  }
}
