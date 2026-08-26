import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/account_providers.dart';
import '../../core/auth/nextcloud_account.dart';
import 'fitness_providers.dart';
import 'fitness_repository.dart';
import 'fitness_settings.dart';
import 'fitness_webdav.dart';

/// Die Einträge des Fitness-Bereichs für den Einstellungs-Bildschirm.
///
/// Bewusst als Liste und nicht als eigener Bildschirm: so fügt es sich in das vorhandene
/// Aufklapp-Panel ein, ohne dessen Aufbau anzufassen.
List<Widget> fitnessSettingsTiles(BuildContext context, WidgetRef ref) {
  final enabled = ref.watch(fitnessEnabledProvider).value ?? false;
  final folder = ref.watch(fitnessFolderProvider).value ?? '';
  final maxHr = ref.watch(fitnessMaxHrProvider).value ?? 0;
  final stepGoal = ref.watch(fitnessStepGoalProvider).value ?? 8000;
  final zones = ref.watch(fitnessZonesProvider);
  final syncing = ref.watch(fitnessSyncingProvider);
  final status = ref.watch(fitnessStatusProvider);
  final data = ref.watch(fitnessDataProvider).value;

  return [
    SwitchListTile(
      secondary: const Icon(Icons.directions_bike_outlined),
      title: const Text('Fitness-Bereich'),
      subtitle: const Text(
        'Blendet „Fitness" in der Navigation ein: Trainings, Schritte und Schlaf',
      ),
      value: enabled,
      onChanged: (v) => ref.read(fitnessEnabledProvider.notifier).set(v),
    ),
    if (enabled) ...[
      ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: const Text('Datenordner in der Nextcloud'),
        subtitle: Text(
          folder.isEmpty ? 'Noch nicht gewählt' : folder,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _chooseFolder(context, ref),
      ),
      ListTile(
        leading: const Icon(Icons.favorite_outline),
        title: const Text('Maximale Herzfrequenz'),
        subtitle: Text(
          maxHr > 0
              ? '$maxHr bpm · Zonen ${zones.labels.join(' · ')}'
              : 'Nicht hinterlegt · Standardzonen ${zones.labels.join(' · ')}'
                  '${_hfmaxHinweis(data)}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _editNumber(
          context,
          titel: 'Maximale Herzfrequenz',
          hinweis: 'Leer lassen für die Standardzonen. Mit einem Wert werden die '
              'Grenzen als 60 / 75 / 85 % der HFmax berechnet.',
          einheit: 'bpm',
          wert: maxHr > 0 ? '$maxHr' : '',
          onSave: (v) => ref.read(fitnessMaxHrProvider.notifier).set(int.tryParse(v) ?? 0),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.directions_walk),
        title: const Text('Schritte-Tagesziel'),
        subtitle: Text('$stepGoal Schritte'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _editNumber(
          context,
          titel: 'Schritte-Tagesziel',
          hinweis: 'Die gestrichelte Linie im Diagramm.',
          einheit: 'Schritte',
          wert: '$stepGoal',
          onSave: (v) =>
              ref.read(fitnessStepGoalProvider.notifier).set(int.tryParse(v) ?? 8000),
        ),
      ),
      ListTile(
        leading: syncing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync),
        title: const Text('Jetzt abgleichen'),
        subtitle: Text(
          status ??
              (data == null
                  ? 'Noch nichts eingelesen'
                  : '${data.activities.length} Einheiten · '
                      '${data.healthDays.length} Tagesdaten'),
        ),
        onTap: syncing || folder.isEmpty
            ? null
            : () => ref.read(fitnessDataProvider.notifier).sync(),
      ),
      ListTile(
        leading: const Icon(Icons.refresh),
        title: const Text('Alles neu einlesen'),
        subtitle: const Text(
          'Liest auch unveränderte Dateien erneut — nötig, wenn sich die '
          'Auswertungslogik geändert hat',
        ),
        onTap: syncing || folder.isEmpty
            ? null
            : () => ref.read(fitnessDataProvider.notifier).sync(force: true),
      ),
      ListTile(
        leading: const Icon(Icons.delete_outline),
        title: const Text('Eingelesene Daten löschen'),
        subtitle: const Text(
          'Entfernt nur die Auswertung, nicht die Dateien in der Nextcloud',
        ),
        onTap: () => ref.read(fitnessDataProvider.notifier).clear(),
      ),
    ],
  ];
}

/// Weist auf eine unpassende Zonen-Einstellung hin.
///
/// Die Standardgrenzen 120/145/160 passen zu einer HFmax um 190. Wer regelmäßig deutlich
/// darüber oder darunter liegt, bekommt sonst Einstufungen, die nicht zu seinem Training
/// passen — etwa jede Ausfahrt als „intensiv".
String _hfmaxHinweis(FitnessData? data) {
  if (data == null || data.activities.isEmpty) return '';
  var hoechster = 0;
  for (final a in data.activities) {
    if (a.hrMax > hoechster) hoechster = a.hrMax;
  }
  if (hoechster < 100) return '';
  return '\nHöchster gemessener Puls bisher: $hoechster bpm';
}

Future<void> _chooseFolder(BuildContext context, WidgetRef ref) async {
  final account = await ref.read(accountProvider.future);
  if (!context.mounted) return;

  if (account == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Erst die Nextcloud einrichten — das geht in den Einstellungen unter Konto.',
        ),
      ),
    );
    return;
  }

  final gewaehlt = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FolderBrowser(account: account),
  );

  if (gewaehlt != null) {
    await ref.read(fitnessFolderProvider.notifier).set(gewaehlt);
    await ref.read(fitnessDataProvider.notifier).sync();
  }
}

/// Blättert durch die Ordner der Nextcloud. Den Pfad von Hand einzutippen wäre die
/// häufigste Fehlerquelle — Groß-/Kleinschreibung und Leerzeichen müssten exakt stimmen.
class _FolderBrowser extends StatefulWidget {
  const _FolderBrowser({required this.account});

  final NextcloudAccount account;

  @override
  State<_FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<_FolderBrowser> {
  static const _client = WebDavClient();

  String _path = '/';
  late Future<List<RemoteEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load(_path);
  }

  Future<List<RemoteEntry>> _load(String path) =>
      _client.list(widget.account, path);

  void _go(String path) {
    setState(() {
      _path = path;
      _future = _load(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    final istWurzel = _path == '/' || _path.isEmpty;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            ListTile(
              leading: istWurzel
                  ? const Icon(Icons.cloud_outlined)
                  : IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      tooltip: 'Eine Ebene höher',
                      onPressed: () {
                        final teile =
                            _path.split('/').where((s) => s.isNotEmpty).toList();
                        teile.removeLast();
                        _go(teile.isEmpty ? '/' : '/${teile.join('/')}');
                      },
                    ),
              title: Text(istWurzel ? 'Nextcloud' : _path),
              subtitle: const Text('Ordner öffnen oder unten übernehmen'),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<RemoteEntry>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '${snap.error}',
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final ordner =
                      (snap.data ?? const <RemoteEntry>[]).where((e) => e.isDirectory);
                  final dateien = (snap.data ?? const <RemoteEntry>[])
                      .where((e) =>
                          e.name.toLowerCase().endsWith('.csv') ||
                          e.name.toLowerCase().endsWith('.md'))
                      .length;

                  return ListView(
                    children: [
                      if (dateien > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            '$dateien auswertbare Datei${dateien == 1 ? '' : 'en'} '
                            'in diesem Ordner',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                      for (final e in ordner)
                        ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(e.name),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _go(e.path),
                        ),
                      if (ordner.isEmpty && dateien == 0)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Dieser Ordner ist leer.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(
                    istWurzel ? 'Gesamte Nextcloud verwenden' : 'Diesen Ordner verwenden',
                  ),
                  onPressed: () => Navigator.of(context).pop(_path),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _editNumber(
  BuildContext context, {
  required String titel,
  required String hinweis,
  required String einheit,
  required String wert,
  required void Function(String) onSave,
}) async {
  final controller = TextEditingController(text: wert);
  final neu = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(hinweis, style: Theme.of(ctx).textTheme.bodySmall),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(suffixText: einheit),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: const Text('Speichern'),
        ),
      ],
    ),
  );
  if (neu != null) onSave(neu);
}
