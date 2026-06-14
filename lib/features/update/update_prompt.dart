import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/platform/platform_support.dart';
import '../../core/update/update_service.dart';

/// Legt sich um die App und prüft **einmal beim Start** (nach dem ersten Frame)
/// auf eine neue Version. Nur Android (dort kann das APK direkt installiert
/// werden). Fehler/keine Updates bleiben still.
class UpdateChecker extends ConsumerStatefulWidget {
  const UpdateChecker({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends ConsumerState<UpdateChecker> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_checked) return;
      _checked = true;
      if (!isAndroid) return;
      runUpdateCheck(context, ref, silentIfNone: true);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Prüft auf Updates und zeigt ggf. einen Dialog. Bei [silentIfNone] = false
/// wird auch eine Rückmeldung gezeigt, wenn alles aktuell ist (für den
/// manuellen „Nach Updates suchen"-Knopf in den Einstellungen).
Future<void> runUpdateCheck(
  BuildContext context,
  WidgetRef ref, {
  bool silentIfNone = false,
}) async {
  final service = ref.read(updateServiceProvider);
  UpdateInfo? info;
  try {
    info = await service.checkForUpdate();
  } catch (_) {
    if (!silentIfNone && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Update-Prüfung fehlgeschlagen. Internet vorhanden?'),
      ));
    }
    return;
  }

  if (!context.mounted) return;
  if (info == null) {
    if (!silentIfNone) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Du hast bereits die neueste Version. ✓'),
      ));
    }
    return;
  }

  await _showUpdateDialog(context, ref, info);
}

Future<void> _showUpdateDialog(
  BuildContext context,
  WidgetRef ref,
  UpdateInfo info,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Neue Version ${info.version}'),
      content: Text(isAndroid
          ? 'Es ist eine neuere Version verfügbar. Möchtest du sie jetzt '
              'herunterladen und installieren?'
          : 'Es ist eine neuere Version verfügbar. Auf der Releases-Seite '
              'herunterladen?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Später'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            if (isAndroid) {
              _downloadWithProgress(context, ref, info);
            } else {
              launchUrl(Uri.parse(info.releaseUrl),
                  mode: LaunchMode.externalApplication);
            }
          },
          child: Text(isAndroid ? 'Herunterladen' : 'Zur Releases-Seite'),
        ),
      ],
    ),
  );
}

Future<void> _downloadWithProgress(
  BuildContext context,
  WidgetRef ref,
  UpdateInfo info,
) async {
  final progress = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Wird heruntergeladen…'),
      content: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, __) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: value == 0 ? null : value),
            const SizedBox(height: 12),
            Text('${(value * 100).toStringAsFixed(0)} %',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );

  try {
    await ref.read(updateServiceProvider).downloadAndInstall(
          info,
          onProgress: (p) => progress.value = p,
        );
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // Fortschritts-Dialog
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Update fehlgeschlagen: $e'),
      ));
    }
  } finally {
    progress.dispose();
  }
}
