import 'fitness_models.dart';

/// Liest die Sportart aus den Begleitdateien einer Fahrt.
///
/// Der Tracker legt jede Tour zusätzlich als `.tcx` und `.json` ab, und **beide nennen
/// die Sportart ausdrücklich** — die TCX als `Sport="Biking"`, die JSON als
/// `"Sport":"bike"`. Damit entfällt jedes Raten über Entfaltung und Spitzentempo, das
/// bei knappen Werten danebenliegen kann.
///
/// Gelesen wird nur der Dateianfang: Die Angabe steht im Kopf, der Rest sind Messpunkte.
class SportHint {
  const SportHint._();

  static final _tcx = RegExp(r'''Sport\s*=\s*["']([A-Za-z]+)["']''');
  static final _json = RegExp(r'''"Sport"\s*:\s*"([A-Za-z]+)"''');

  /// Sucht die Angabe im Kopf einer TCX- oder JSON-Datei.
  static Sport? parse(String head) {
    final treffer = _tcx.firstMatch(head) ?? _json.firstMatch(head);
    if (treffer == null) return null;
    return fromName(treffer.group(1)!);
  }

  /// Ordnet die Bezeichnungen beider Formate zu.
  static Sport? fromName(String raw) {
    final n = raw.toLowerCase();
    const rad = ['biking', 'bike', 'cycling', 'ride'];
    const lauf = ['running', 'run', 'jogging'];
    if (rad.contains(n)) return Sport.cycling;
    if (lauf.contains(n)) return Sport.running;
    // „other", „walking", „multisport": bewusst kein Ergebnis statt einer
    // Falschzuordnung — dann greift wieder die Schätzung aus den Messwerten.
    return null;
  }

  /// Dateinamen der möglichen Begleitdateien zu einer CSV.
  ///
  /// Beide liegen unter demselben Namensstamm wie die CSV — `2026-08-25_190102.csv`
  /// gehört zu `2026-08-25_190102.tcx` und `.json`.
  static List<String> companionNames(String csvName) {
    final stamm = csvName.toLowerCase().endsWith('.csv')
        ? csvName.substring(0, csvName.length - 4)
        : csvName;
    return ['$stamm.tcx', '$stamm.json'];
  }
}
