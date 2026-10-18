import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fitness_models.dart';
import 'fitness_providers.dart';
import 'fitness_widgets.dart';
import 'health_connect_mapping.dart';
import 'health_connect_source.dart';

/// Prüfansicht für Health Connect: Was kommt auf diesem Handy an, von welcher App, und
/// passt es zu den Tageswerten aus den Dateien in der Nextcloud?
///
/// Bewusst nur lesen und zeigen — zum Nachsehen, wenn ein Wert merkwürdig aussieht.
class HealthConnectScreen extends ConsumerStatefulWidget {
  const HealthConnectScreen({super.key});

  @override
  ConsumerState<HealthConnectScreen> createState() => _HealthConnectScreenState();
}

class _HealthConnectScreenState extends ConsumerState<HealthConnectScreen> {
  final _quelle = HealthConnectSource();
  HcStatus? _status;
  HcAbruf? _abruf;
  bool _laeuft = false;
  String? _meldung;

  @override
  void initState() {
    super.initState();
    _pruefen();
  }

  Future<void> _pruefen() async {
    final s = await _quelle.status();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _ausfuehren(Future<void> Function() schritt) async {
    setState(() {
      _laeuft = true;
      _meldung = null;
    });
    try {
      await schritt();
    } catch (e) {
      _meldung = 'Fehler: $e';
    } finally {
      if (mounted) setState(() => _laeuft = false);
    }
  }

  Future<void> _zugriff() => _ausfuehren(() async {
        final ok = await _quelle.zugriffAnfragen();
        _meldung = ok
            ? 'Zugriff erteilt.'
            : 'Nicht alle Rechte erteilt — die Übersicht unten zeigt, was fehlt.';
      });

  Future<void> _holen() => _ausfuehren(() async {
        final jetzt = DateTime.now();
        final von = DateTime(jetzt.year, jetzt.month, jetzt.day - 6);
        _abruf = await _quelle.abrufen(von: von, bis: jetzt);
      });

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final abruf = _abruf;
    final ausDateien = {
      for (final h in ref.watch(fitnessDataProvider).value?.healthDays ?? const <HealthDay>[])
        h.date: h,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Health Connect – Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        children: [
          FitnessCard(
            title: 'Verbindung',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(switch (_status) {
                  null => 'Wird geprüft …',
                  HcStatus.nichtAndroid => 'Health Connect gibt es nur unter Android.',
                  HcStatus.nichtInstalliert => 'Health Connect ist nicht verfügbar.',
                  HcStatus.updateNoetig => 'Health Connect muss aktualisiert werden.',
                  HcStatus.bereit => 'Health Connect ist bereit.',
                }),
                const SizedBox(height: 10),
                if (_status == HcStatus.nichtInstalliert ||
                    _status == HcStatus.updateNoetig)
                  FilledButton(
                    onPressed: _laeuft ? null : () => _ausfuehren(_quelle.installieren),
                    child: const Text('Health Connect installieren / aktualisieren'),
                  ),
                if (_status == HcStatus.bereit) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Zugriff erlauben'),
                    onPressed: _laeuft ? null : _zugriff,
                  ),
                  const SizedBox(height: 6),
                  FilledButton.icon(
                    icon: _laeuft
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Letzte 7 Tage holen'),
                    onPressed: _laeuft ? null : _holen,
                  ),
                ],
                if (_meldung != null) ...[
                  const SizedBox(height: 8),
                  Text(_meldung!, style: grau),
                ],
                const SizedBox(height: 8),
                Text(
                  'Diese Ansicht liest nur und zeigt an. Gespeichert wird über den '
                  'Schalter „Gesundheitsdaten aus Health Connect" in den Einstellungen.',
                  style: grau,
                ),
              ],
            ),
          ),
          if (abruf != null) ...[
            FitnessCard(
              title: 'Rechte',
              child: FitnessValueGrid(values: [
                ('Im Hintergrund lesen', abruf.hintergrund ? '✅ ja' : '❌ nein'),
                ('Älter als 30 Tage', abruf.verlauf ? '✅ ja' : '❌ nein'),
              ]),
            ),
            _QuellenKarte(abruf: abruf),
            if (abruf.workouts.isNotEmpty) _TrainingsKarte(abruf: abruf),
            _TageKarte(abruf: abruf, ausDateien: ausDateien),
            if (abruf.fehler.isNotEmpty)
              FitnessCard(
                title: 'Nicht lesbar',
                subtitle: 'Meist fehlt dafür die Berechtigung',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in abruf.fehler.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('${e.key}: ${e.value}', style: grau),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Je Art: wie viele Werte von welcher App. Daran sieht man, ob Huawei wirklich liefert
/// und ob mehrere Apps dasselbe eintragen.
class _QuellenKarte extends StatelessWidget {
  const _QuellenKarte({required this.abruf});

  final HcAbruf abruf;

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final zaehler = <HcKind, Map<String, int>>{};
    for (final s in abruf.samples) {
      final m = zaehler.putIfAbsent(s.kind, () => {});
      m[s.source] = (m[s.source] ?? 0) + 1;
    }
    final genutzt = dominantSources(abruf.samples);

    return FitnessCard(
      title: 'Was ankommt',
      subtitle: 'Werte je Art und App · ★ = wird verwendet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final k in HcKind.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(hcKindLabel(k),
                        style: Theme.of(context).textTheme.bodyMedium),
                  ),
                  Expanded(
                    child: Text(
                      zaehler[k] == null
                          ? '—'
                          : [
                              for (final e in zaehler[k]!.entries)
                                '${genutzt[k] == e.key ? '★ ' : ''}${e.key}: ${e.value}',
                            ].join('\n'),
                      style: grau,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TrainingsKarte extends StatelessWidget {
  const _TrainingsKarte({required this.abruf});

  final HcAbruf abruf;

  /// Was es zu einer Einheit an Verlauf gibt — davon hängt ab, ob sie mit Karte und
  /// Tempo erscheinen kann.
  String _verlauf(HcWorkout w) {
    bool drin(DateTime t) => !t.isBefore(w.from) && !t.isAfter(w.to);
    final tempo = abruf.samples.where((s) => s.kind == HcKind.speed && drin(s.from)).length;
    final puls = abruf.samples.where((s) => s.kind == HcKind.heartRate && drin(s.from)).length;
    final gps = [
      for (final r in abruf.routes)
        for (final p in r.points)
          if (drin(p.time)) p,
    ].length;
    return 'Puls $puls · Tempo $tempo · GPS $gps Punkte';
  }

  @override
  Widget build(BuildContext context) {
    final grau = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    final sortiert = [...abruf.workouts]..sort((a, b) => b.from.compareTo(a.from));
    return FitnessCard(
      title: 'Trainings',
      subtitle: 'Mit Tempo oder GPS entsteht eine Fahrt mit Verlauf und Karte. Keine '
          'GPS-Punkte? In Health Connect bei dieser App „Trainingsstrecken: Immer '
          'erlauben" setzen.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final w in sortiert)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${dayKey(w.from)} ${w.from.hour.toString().padLeft(2, '0')}:'
                '${w.from.minute.toString().padLeft(2, '0')} · ${w.type} · '
                '${w.minutes} Min'
                '${w.distanceM != null && w.distanceM! > 0 ? ' · ${(w.distanceM! / 1000).toStringAsFixed(1)} km' : ''}'
                ' · ${w.source}\n${_verlauf(w)}',
                style: grau,
              ),
            ),
        ],
      ),
    );
  }
}

/// Tageswerte aus Health Connect neben denen aus den Dateien — so sieht man auf einen
/// Blick, ob beide dasselbe sagen.
class _TageKarte extends StatelessWidget {
  const _TageKarte({required this.abruf, required this.ausDateien});

  final HcAbruf abruf;
  final Map<String, HealthDay> ausDateien;

  @override
  Widget build(BuildContext context) {
    final tage = healthDaysFromHc(
      samples: abruf.samples,
      workouts: abruf.workouts,
      stepsPerDay: abruf.stepsPerDay,
    ).reversed.toList();
    final grau = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

    String zahl(num? v, [int stellen = 0]) =>
        v == null ? '—' : v.toStringAsFixed(stellen);
    String vergleich(num? hc, num? datei, [int stellen = 0]) =>
        datei == null ? zahl(hc, stellen) : '${zahl(hc, stellen)}  (Datei ${zahl(datei, stellen)})';

    return FitnessCard(
      title: 'Tageswerte',
      subtitle: 'Health Connect · in Klammern der Wert aus der Nextcloud-Datei',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tage.isEmpty) Text('Keine Daten in den letzten 7 Tagen.', style: grau),
          for (final t in tage) ...[
            Text(t.date, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            FitnessValueGrid(values: [
              ('Schritte', vergleich(t.steps, ausDateien[t.date]?.steps)),
              ('Schlaf (h)', vergleich(t.sleepHours, ausDateien[t.date]?.sleepHours, 1)),
              ('Tiefschlaf (h)',
                  vergleich(t.sleepDeepHours, ausDateien[t.date]?.sleepDeepHours, 1)),
              ('Ruhepuls', vergleich(t.restingHr, ausDateien[t.date]?.restingHr)),
              ('Ø Puls', vergleich(t.hrAvg, ausDateien[t.date]?.hrAvg)),
              ('SpO₂ Ø', vergleich(t.spo2Avg, ausDateien[t.date]?.spo2Avg)),
              ('Gewicht', vergleich(t.weightKg, ausDateien[t.date]?.weightKg, 1)),
              ('kcal aktiv',
                  vergleich(t.activeCalories, ausDateien[t.date]?.activeCalories)),
              ('kcal gesamt',
                  vergleich(t.totalCalories, ausDateien[t.date]?.totalCalories)),
              ('Distanz (km)',
                  vergleich(t.walkingRunningKm, ausDateien[t.date]?.walkingRunningKm, 1)),
            ]),
            const Divider(height: 20),
          ],
        ],
      ),
    );
  }
}
