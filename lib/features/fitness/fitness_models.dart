/// Datenmodell der Trainingsauswertung.
///
/// Portiert aus der eigenständigen Kotlin-App (pbrockt/Trainingsauswertung). Die
/// inhaltlichen Entscheidungen sind dort gegen echte Daten geprüft und hier bewusst
/// unverändert übernommen — die Kommentare halten fest, *warum* etwas so ist, weil das
/// aus dem Code allein nicht hervorgeht.
library;

/// Größe des Puls-Histogramms: bpm 0..255 deckt jeden realistischen Messwert ab.
const int hrHistogramSize = 256;

enum Sport { cycling, running, unknown }

String sportLabel(Sport s) => switch (s) {
      Sport.cycling => 'Radfahren',
      Sport.running => 'Laufen',
      Sport.unknown => 'Unbekannt',
    };

String sportIcon(Sport s) => switch (s) {
      Sport.cycling => '\u{1F6B4}',
      Sport.running => '\u{1F3C3}',
      Sport.unknown => '\u{2753}',
    };

/// Art einer Einheit. Entscheidet, wie sie bewertet wird — nicht nur, wie sie heißt.
///
/// Der eigentliche Zweck ist [SessionType.ausflug]: eine gemütliche Familienrunde hat ein
/// niedriges Tempo, ohne dass die Form schlechter geworden wäre. Fließt sie in die Trends
/// ein, meldet die App einen Rückschritt, den es nicht gibt — und das genau dann, wenn man
/// eigentlich etwas richtig gemacht hat.
enum SessionType {
  /// Normales Training. Zählt voll in alle Trends.
  training,

  /// Harte Einheit, Intervalle. Zählt in die Trends, wird aber anders kommentiert.
  intensiv,

  /// Familienausflug, Alltagsfahrt. Zählt in Distanz und Belastung, nicht in die Trends.
  ausflug,
}

String sessionTypeLabel(SessionType t) => switch (t) {
      SessionType.training => 'Training',
      SessionType.intensiv => 'Intensiv',
      SessionType.ausflug => 'Ausflug',
    };

String sessionTypeIcon(SessionType t) => switch (t) {
      SessionType.training => '\u{1F3AF}',
      SessionType.intensiv => '\u{1F525}',
      SessionType.ausflug => '\u{1F9FA}',
    };

/// Ein Messpunkt im heruntergerechneten Verlauf einer Einheit.
class TrackPoint {
  const TrackPoint({
    required this.elapsedSec,
    required this.hr,
    required this.speedKmh,
    required this.cadence,
    required this.altitude,
    this.lat,
    this.lon,
    this.extra = const {},
  });

  final int elapsedSec;
  final int hr;
  final double speedKmh;
  final int cadence;
  final double altitude;

  /// Position, falls der Tracker sie mitschreibt. Ohne sie gibt es keine Streckenkarte.
  final double? lat;
  final double? lon;

  /// Alle weiteren Zahlenspalten der CSV, unter ihrem Spaltennamen.
  final Map<String, double> extra;

  Map<String, dynamic> toJson() => {
        's': elapsedSec,
        'h': hr,
        'v': speedKmh,
        'c': cadence,
        'a': altitude,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (extra.isNotEmpty) 'x': extra,
      };

  factory TrackPoint.fromJson(Map<String, dynamic> j) => TrackPoint(
        elapsedSec: (j['s'] as num?)?.toInt() ?? 0,
        hr: (j['h'] as num?)?.toInt() ?? 0,
        speedKmh: (j['v'] as num?)?.toDouble() ?? 0,
        cadence: (j['c'] as num?)?.toInt() ?? 0,
        altitude: (j['a'] as num?)?.toDouble() ?? 0,
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        extra: (j['x'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()),
            ) ??
            const {},
      );
}

/// Kennzahlen einer beliebigen Messspalte, damit auch unbekannte Spalten etwas aussagen.
class ChannelStat {
  const ChannelStat({
    required this.name,
    required this.min,
    required this.max,
    required this.avg,
    required this.count,
  });

  final String name;
  final double min;
  final double max;
  final double avg;
  final int count;

  Map<String, dynamic> toJson() =>
      {'n': name, 'lo': min, 'hi': max, 'av': avg, 'c': count};

  factory ChannelStat.fromJson(Map<String, dynamic> j) => ChannelStat(
        name: j['n'] as String,
        min: (j['lo'] as num).toDouble(),
        max: (j['hi'] as num).toDouble(),
        avg: (j['av'] as num).toDouble(),
        count: (j['c'] as num).toInt(),
      );
}

/// Eine ausgewertete Trainingseinheit.
///
/// Wichtig: hier stehen bewusst KEINE fertigen Pulszonen-Anteile, sondern das rohe
/// [hrHistogram] (Index = bpm, Wert = Anzahl Sekunden). Die Zonengrenzen hängen an der
/// eingestellten maximalen Herzfrequenz — wären sie eingerechnet, müsste beim Ändern der
/// Einstellung alles neu eingelesen werden.
class Activity {
  const Activity({
    required this.id,
    required this.date,
    required this.timeOfDay,
    required this.sportDetected,
    required this.sportConfidence,
    required this.durationSec,
    required this.distanceKm,
    required this.hrAvg,
    required this.hrMax,
    required this.hrHistogram,
    required this.cadenceAvg,
    required this.speedAvgKmh,
    required this.speedMaxKmh,
    this.speedMovingAvgKmh = 0,
    required this.elevGain,
    required this.elevLoss,
    required this.series,
    this.stoppedShare = 0,
    this.channels = const {},
  });

  final String id;

  /// yyyy-MM-dd.
  final String date;

  /// HH:mm.
  final String timeOfDay;

  final Sport sportDetected;
  final double sportConfidence;
  final int durationSec;
  final double distanceKm;
  final int hrAvg;
  final int hrMax;
  final List<int> hrHistogram;
  final int cadenceAvg;
  final double speedAvgKmh;
  final double speedMaxKmh;

  /// Schnitt nur über die Zeit in Bewegung.
  ///
  /// Der Gesamtschnitt rechnet Ampeln und Pausen mit — auf einer Runde durch den Ort
  /// drückt das den Wert spürbar, ohne dass man langsamer gefahren wäre.
  final double speedMovingAvgKmh;
  final int elevGain;
  final int elevLoss;
  final List<TrackPoint> series;

  /// Anteil der Messpunkte im Stillstand. Trennt eine Ausflugsrunde mit vielen Pausen von
  /// einer durchgefahrenen Trainingseinheit.
  final double stoppedShare;

  /// Kennzahlen zu allen weiteren Spalten der CSV — was der Tracker sonst noch liefert,
  /// geht damit nicht verloren, auch wenn die App die Spalte nicht kennt.
  final Map<String, ChannelStat> channels;

  /// Hat die Einheit eine aufgezeichnete Strecke?
  bool get hasTrack => series.any((p) => p.lat != null && p.lon != null);

  /// Meter pro Kurbel- bzw. Schrittzyklus — der Wert, an dem die Sportart hängt.
  double get metersPerCycle =>
      cadenceAvg > 0 ? (speedAvgKmh / 3.6 * 60.0) / cadenceAvg : 0;

  /// Tempo in Sekunden pro Kilometer (fürs Laufen die aussagekräftigere Größe).
  int get paceSecPerKm =>
      distanceKm > 0.01 ? (durationSec / distanceKm).round() : 0;

  Activity copyWith({
    String? id,
    String? date,
    double? speedAvgKmh,
    double? stoppedShare,
  }) =>
      Activity(
        id: id ?? this.id,
        date: date ?? this.date,
        timeOfDay: timeOfDay,
        sportDetected: sportDetected,
        sportConfidence: sportConfidence,
        durationSec: durationSec,
        distanceKm: distanceKm,
        hrAvg: hrAvg,
        hrMax: hrMax,
        hrHistogram: hrHistogram,
        cadenceAvg: cadenceAvg,
        speedAvgKmh: speedAvgKmh ?? this.speedAvgKmh,
        speedMaxKmh: speedMaxKmh,
        speedMovingAvgKmh: speedMovingAvgKmh,
        elevGain: elevGain,
        elevLoss: elevLoss,
        series: series,
        stoppedShare: stoppedShare ?? this.stoppedShare,
        channels: channels,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'time': timeOfDay,
        'sport': sportDetected.name,
        'conf': sportConfidence,
        'dur': durationSec,
        'km': distanceKm,
        'hrAvg': hrAvg,
        'hrMax': hrMax,
        'hist': hrHistogram,
        'cad': cadenceAvg,
        'vAvg': speedAvgKmh,
        'vMax': speedMaxKmh,
        'vMove': speedMovingAvgKmh,
        'up': elevGain,
        'down': elevLoss,
        'stop': stoppedShare,
        'chan': channels.map((k, v) => MapEntry(k, v.toJson())),
        'series': series.map((p) => p.toJson()).toList(),
      };

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: j['id'] as String,
        date: j['date'] as String? ?? 'unbekannt',
        timeOfDay: j['time'] as String? ?? '',
        sportDetected: Sport.values.firstWhere(
          (s) => s.name == j['sport'],
          orElse: () => Sport.unknown,
        ),
        sportConfidence: (j['conf'] as num?)?.toDouble() ?? 0,
        durationSec: (j['dur'] as num?)?.toInt() ?? 0,
        distanceKm: (j['km'] as num?)?.toDouble() ?? 0,
        hrAvg: (j['hrAvg'] as num?)?.toInt() ?? 0,
        hrMax: (j['hrMax'] as num?)?.toInt() ?? 0,
        hrHistogram:
            (j['hist'] as List?)?.map((e) => (e as num).toInt()).toList() ??
                List<int>.filled(hrHistogramSize, 0),
        cadenceAvg: (j['cad'] as num?)?.toInt() ?? 0,
        speedAvgKmh: (j['vAvg'] as num?)?.toDouble() ?? 0,
        speedMaxKmh: (j['vMax'] as num?)?.toDouble() ?? 0,
        speedMovingAvgKmh: (j['vMove'] as num?)?.toDouble() ?? 0,
        elevGain: (j['up'] as num?)?.toInt() ?? 0,
        elevLoss: (j['down'] as num?)?.toInt() ?? 0,
        stoppedShare: (j['stop'] as num?)?.toDouble() ?? 0,
        channels: (j['chan'] as Map?)?.map(
              (k, v) => MapEntry(
                k as String,
                ChannelStat.fromJson(v as Map<String, dynamic>),
              ),
            ) ??
            const {},
        series: (j['series'] as List?)
                ?.map((e) => TrackPoint.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// Tages-Gesundheitsdaten aus einer .md-Datei.
class HealthDay {
  const HealthDay({
    required this.date,
    this.steps,
    this.sleepHours,
    this.activeCalories,
    this.totalCalories,
    this.hrAvg,
    this.hrMin,
    this.hrMax,
    this.spo2Avg,
    this.spo2Min,
    this.weightKg,
    this.restingHr,
    this.basalCalories,
    this.walkingRunningKm,
    this.exerciseMinutes,
    this.workoutCount,
    this.workoutMinutes,
    this.workoutDistanceKm,
    this.workoutAvgHr,
    this.workouts = const [],
    this.sleepDeepHours,
    this.sleepRemHours,
    this.sleepCoreHours,
    this.sleepAwakeHours,
    this.bedtime,
    this.wakeTime,
  });

  final String date;
  final int? steps;
  final double? sleepHours;
  final int? activeCalories;
  final int? totalCalories;
  final int? hrAvg;
  final int? hrMin;
  final int? hrMax;
  final int? spo2Avg;
  final int? spo2Min;

  /// Manche Tracker schreiben das Gewicht mit ins Frontmatter — dann wird es übernommen.
  final double? weightKg;

  /// Vom Tracker ermittelter Ruhepuls.
  ///
  /// Nicht dasselbe wie [hrMin]: das Tagesminimum wird oft im Tiefschlaf gemessen und
  /// liegt deutlich darunter. Für den Formverlauf ist dieser Wert der richtige.
  final int? restingHr;

  final int? basalCalories;
  final double? walkingRunningKm;

  /// Bewegungsminuten des Tages laut Tracker.
  final int? exerciseMinutes;

  /// Aufgezeichnete Trainingseinheiten des Tages — auch solche ohne eigene CSV.
  final int? workoutCount;
  final int? workoutMinutes;
  final double? workoutDistanceKm;
  final int? workoutAvgHr;

  /// Art der Einheiten, wie der Tracker sie nennt (`walking`, `other`, …).
  final List<String> workouts;

  /// Schlafphasen in Stunden.
  final double? sleepDeepHours;
  final double? sleepRemHours;
  final double? sleepCoreHours;
  final double? sleepAwakeHours;

  /// Zubettgeh- und Aufstehzeit als `HH:mm`.
  final String? bedtime;
  final String? wakeTime;

  Map<String, dynamic> toJson() => {
        'date': date,
        'steps': steps,
        'sleep': sleepHours,
        'kcalActive': activeCalories,
        'kcal': totalCalories,
        'hrAvg': hrAvg,
        'hrMin': hrMin,
        'hrMax': hrMax,
        'spo2': spo2Avg,
        'spo2Min': spo2Min,
        'kg': weightKg,
        'rhr': restingHr,
        'basal': basalCalories,
        'walkKm': walkingRunningKm,
        'exMin': exerciseMinutes,
        'woCount': workoutCount,
        'woMin': workoutMinutes,
        'woKm': workoutDistanceKm,
        'woHr': workoutAvgHr,
        'wo': workouts,
        'sDeep': sleepDeepHours,
        'sRem': sleepRemHours,
        'sCore': sleepCoreHours,
        'sAwake': sleepAwakeHours,
        'bed': bedtime,
        'wake': wakeTime,
      };

  factory HealthDay.fromJson(Map<String, dynamic> j) => HealthDay(
        date: j['date'] as String,
        steps: (j['steps'] as num?)?.toInt(),
        sleepHours: (j['sleep'] as num?)?.toDouble(),
        activeCalories: (j['kcalActive'] as num?)?.toInt(),
        totalCalories: (j['kcal'] as num?)?.toInt(),
        hrAvg: (j['hrAvg'] as num?)?.toInt(),
        hrMin: (j['hrMin'] as num?)?.toInt(),
        hrMax: (j['hrMax'] as num?)?.toInt(),
        spo2Avg: (j['spo2'] as num?)?.toInt(),
        spo2Min: (j['spo2Min'] as num?)?.toInt(),
        weightKg: (j['kg'] as num?)?.toDouble(),
        restingHr: (j['rhr'] as num?)?.toInt(),
        basalCalories: (j['basal'] as num?)?.toInt(),
        walkingRunningKm: (j['walkKm'] as num?)?.toDouble(),
        exerciseMinutes: (j['exMin'] as num?)?.toInt(),
        workoutCount: (j['woCount'] as num?)?.toInt(),
        workoutMinutes: (j['woMin'] as num?)?.toInt(),
        workoutDistanceKm: (j['woKm'] as num?)?.toDouble(),
        workoutAvgHr: (j['woHr'] as num?)?.toInt(),
        workouts:
            (j['wo'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        sleepDeepHours: (j['sDeep'] as num?)?.toDouble(),
        sleepRemHours: (j['sRem'] as num?)?.toDouble(),
        sleepCoreHours: (j['sCore'] as num?)?.toDouble(),
        sleepAwakeHours: (j['sAwake'] as num?)?.toDouble(),
        bedtime: j['bed'] as String?,
        wakeTime: j['wake'] as String?,
      );
}

/// Ein gewogener Wert. Datum als yyyy-MM-dd, wie überall sonst.
class WeightEntry {
  const WeightEntry(this.date, this.kg, {this.time});

  final String date;
  final double kg;

  /// Uhrzeit des Wiegens als `HH:mm`, falls angegeben.
  ///
  /// Nicht Zierde: das Gewicht schwankt über den Tag um bis zu zwei Kilo. Ein Wert vom
  /// Abend ist mit einem Morgenwert nicht vergleichbar — die App kann darauf hinweisen,
  /// statt den Ausreißer stillschweigend in den Trend zu rechnen.
  final String? time;

  /// Stunde des Wiegens, falls bekannt.
  int? get hour {
    final t = time;
    if (t == null || t.length < 2) return null;
    return int.tryParse(t.substring(0, 2));
  }

  Map<String, dynamic> toJson() =>
      {'date': date, 'kg': kg, if (time != null) 'time': time};

  factory WeightEntry.fromJson(Map<String, dynamic> j) => WeightEntry(
        j['date'] as String,
        (j['kg'] as num).toDouble(),
        time: j['time'] as String?,
      );
}

/// Die drei Pulszonen-Grenzen.
///
/// Ohne hinterlegte maximale Herzfrequenz gelten die Festwerte 120/145/160; ist eine HFmax
/// eingestellt, werden daraus 60/75/85 % abgeleitet.
class HrZones {
  const HrZones(this.t1, this.t2, this.t3);

  final int t1;
  final int t2;
  final int t3;

  static const HrZones standard = HrZones(120, 145, 160);

  factory HrZones.forMaxHr(int? maxHr) {
    if (maxHr == null || maxHr < 120) return standard;
    return HrZones(
      (maxHr * 0.60).round(),
      (maxHr * 0.75).round(),
      (maxHr * 0.85).round(),
    );
  }

  List<String> get labels => ['< $t1', '$t1–$t2', '$t2–$t3', '> $t3'];

  int indexOf(int bpm) {
    if (bpm < t1) return 0;
    if (bpm < t2) return 1;
    if (bpm < t3) return 2;
    return 3;
  }

  /// Verteilt ein Puls-Histogramm auf die vier Zonen (Sekunden je Zone).
  List<int> distribute(List<int> histogram) {
    final out = List<int>.filled(4, 0);
    for (var bpm = 1; bpm < histogram.length; bpm++) {
      final count = histogram[bpm];
      if (count > 0) out[indexOf(bpm)] += count;
    }
    return out;
  }

  /// Anteil der Zeit über der zweiten Schwelle — der "intensive" Block.
  int hardSharePercent(List<int> histogram) {
    final d = distribute(histogram);
    final total = d.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 0;
    return ((d[2] + d[3]) * 100 / total).round();
  }

  @override
  bool operator ==(Object other) =>
      other is HrZones && other.t1 == t1 && other.t2 == t2 && other.t3 == t3;

  @override
  int get hashCode => Object.hash(t1, t2, t3);

  @override
  String toString() => 'HrZones($t1/$t2/$t3)';
}
