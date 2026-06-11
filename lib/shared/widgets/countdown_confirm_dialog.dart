import 'dart:async';

import 'package:flutter/material.dart';

/// Zeigt einen Lösch-Bestätigungsdialog, dessen Bestätigen-Button erst nach
/// [seconds] Sekunden klickbar wird (Schutz vor versehentlichem Löschen).
/// Gibt `true` zurück, wenn bestätigt wurde.
Future<bool> showCountdownDeleteDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Löschen',
  int seconds = 5,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _CountdownDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      seconds: seconds,
    ),
  );
  return result ?? false;
}

class _CountdownDialog extends StatefulWidget {
  const _CountdownDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.seconds,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final int seconds;

  @override
  State<_CountdownDialog> createState() => _CountdownDialogState();
}

class _CountdownDialogState extends State<_CountdownDialog> {
  late int _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _remaining = 0);
      } else {
        setState(() => _remaining--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ready = _remaining == 0;
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: Text(widget.title),
      content: Text(widget.message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ready ? scheme.error : scheme.surfaceContainerHighest,
            foregroundColor: ready ? scheme.onError : scheme.onSurfaceVariant,
          ),
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          child: Text(ready
              ? widget.confirmLabel
              : '${widget.confirmLabel} ($_remaining)'),
        ),
      ],
    );
  }
}
