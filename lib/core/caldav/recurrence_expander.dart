import 'package:enough_icalendar/enough_icalendar.dart';

/// Expandiert eine Wiederholungsregel (RRULE) in einzelne Termin-Starts
/// innerhalb eines Zeitfensters.
///
/// Unterstützt die im Familienalltag üblichen Fälle: täglich / wöchentlich
/// (auch mit BYDAY) / monatlich / jährlich, jeweils mit INTERVAL und Limit
/// per COUNT oder UNTIL. Sekunden-/Minuten-/Stunden-Frequenzen werden nur
/// als Basis-Instanz behandelt.
class RecurrenceExpander {
  const RecurrenceExpander();

  List<DateTime> expand(
    DateTime start,
    Recurrence rule, {
    required DateTime windowStart,
    required DateTime windowEnd,
    int maxOccurrences = 1000,
  }) {
    final result = <DateTime>[];
    final interval = rule.interval < 1 ? 1 : rule.interval;
    final until = rule.until;
    final count = rule.count;
    var generated = 0;

    bool stop(DateTime occ) =>
        (until != null && occ.isAfter(until)) ||
        (count != null && generated >= count) ||
        occ.isAfter(windowEnd) ||
        generated >= maxOccurrences;

    void take(DateTime occ) {
      generated++;
      if (!occ.isBefore(windowStart)) result.add(occ);
    }

    switch (rule.frequency) {
      case RecurrenceFrequency.daily:
        var occ = start;
        while (!stop(occ)) {
          take(occ);
          occ = occ.add(Duration(days: interval));
        }

      case RecurrenceFrequency.weekly:
        final weekdays = rule.hasByWeekDay
            ? (rule.byWeekDay!.map((d) => d.weekday).toSet().toList()..sort())
            : [start.weekday];
        // Montag der Startwoche, mit der Uhrzeit des Serienstarts.
        final startMonday =
            _atTimeOf(start, start.subtract(Duration(days: start.weekday - 1)));
        var block = 0;
        outer:
        while (true) {
          final weekStart =
              startMonday.add(Duration(days: block * 7 * interval));
          if (weekStart.isAfter(windowEnd)) break;
          for (final wd in weekdays) {
            final occ = _atTimeOf(start, weekStart.add(Duration(days: wd - 1)));
            if (occ.isBefore(start)) continue;
            if (stop(occ)) break outer;
            take(occ);
          }
          block++;
        }

      case RecurrenceFrequency.monthly:
        var n = 0;
        while (true) {
          final occ = _addMonths(start, n * interval);
          if (stop(occ)) break;
          take(occ);
          n++;
        }

      case RecurrenceFrequency.yearly:
        var n = 0;
        while (true) {
          final occ = _addMonths(start, n * interval * 12);
          if (stop(occ)) break;
          take(occ);
          n++;
        }

      default:
        if (!start.isBefore(windowStart) && !start.isAfter(windowEnd)) {
          result.add(start);
        }
    }
    return result;
  }

  /// Datum aus [date], Uhrzeit aus [timeSource].
  DateTime _atTimeOf(DateTime timeSource, DateTime date) => DateTime(
        date.year,
        date.month,
        date.day,
        timeSource.hour,
        timeSource.minute,
        timeSource.second,
      );

  /// Addiert Monate und kappt den Tag auf den letzten gültigen (z.B. 31. → 28.).
  DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = d.day > lastDay ? lastDay : d.day;
    return DateTime(year, month, day, d.hour, d.minute, d.second);
  }
}
