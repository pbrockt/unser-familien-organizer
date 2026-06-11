import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Releases-Seite des Projekts – hier liegt jeweils das neueste APK.
const String kReleasesUrl =
    'https://github.com/pbrockt/FamilyPlanner/releases';

/// Zeigt ein Bottom-Sheet mit aktueller App-Version und einem Button, der
/// die GitHub-Releases-Seite öffnet (dort kann das neueste APK geladen
/// werden – das Repo ist privat, daher Download im eingeloggten Browser).
Future<void> showAboutUpdateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _AboutUpdateSheet(),
  );
}

class _AboutUpdateSheet extends StatelessWidget {
  const _AboutUpdateSheet();

  Future<void> _openReleases(BuildContext context) async {
    final uri = Uri.parse(kReleasesUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konnte den Browser nicht öffnen. Adresse: '
              'github.com/pbrockt/FamilyPlanner/releases'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.system_update, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text('App aktualisieren',
                    style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final info = snapshot.data;
                final version = info == null
                    ? '…'
                    : '${info.version} (${info.buildNumber})';
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Installierte Version'),
                    subtitle: Text(version),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Text(
              'Die neueste Version liegt auf GitHub unter „Releases". '
              'Öffne die Seite, lade das aktuellste APK herunter und '
              'installiere es über die alte Version drüber – deine '
              'Verbindung bleibt erhalten.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _openReleases(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Releases öffnen & APK laden'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
