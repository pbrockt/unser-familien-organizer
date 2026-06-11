import 'package:enough_icalendar/enough_icalendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/caldav/recurrence_expander.dart';

void main() {
  const expander = RecurrenceExpander();
  final windowStart = DateTime(2026, 1, 1);
  final windowEnd = DateTime(2027, 12, 31);

  List<DateTime> exp(DateTime start, Recurrence r) => expander.expand(
        start,
        r,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

  test('täglich mit COUNT=3 ergibt 3 aufeinanderfolgende Tage', () {
    final start = DateTime(2026, 6, 10, 9, 0);
    final occ = exp(start, const Recurrence(RecurrenceFrequency.daily, count: 3));
    expect(occ, hasLength(3));
    expect(occ[0], start);
    expect(occ[1], DateTime(2026, 6, 11, 9, 0));
    expect(occ[2], DateTime(2026, 6, 12, 9, 0));
  });

  test('täglich mit INTERVAL=2 überspringt jeden zweiten Tag', () {
    final start = DateTime(2026, 6, 10);
    final occ = exp(
      start,
      const Recurrence(RecurrenceFrequency.daily, count: 3, interval: 2),
    );
    expect(occ, [
      DateTime(2026, 6, 10),
      DateTime(2026, 6, 12),
      DateTime(2026, 6, 14),
    ]);
  });

  test('wöchentlich mit BYDAY MO,WE liegt nur auf Mo und Mi', () {
    final start = DateTime(2026, 6, 3); // Mittwoch
    final occ = exp(
      start,
      const Recurrence(
        RecurrenceFrequency.weekly,
        count: 6,
        byWeekDay: [
          ByDayRule(DateTime.monday),
          ByDayRule(DateTime.wednesday),
        ],
      ),
    );
    expect(occ, hasLength(6));
    expect(
      occ.every((d) =>
          d.weekday == DateTime.monday || d.weekday == DateTime.wednesday),
      isTrue,
    );
    // Chronologisch aufsteigend.
    for (var i = 1; i < occ.length; i++) {
      expect(occ[i].isAfter(occ[i - 1]), isTrue);
    }
  });

  test('monatlich mit COUNT=3 erhöht den Monat', () {
    final start = DateTime(2026, 1, 15);
    final occ =
        exp(start, const Recurrence(RecurrenceFrequency.monthly, count: 3));
    expect(occ, [
      DateTime(2026, 1, 15),
      DateTime(2026, 2, 15),
      DateTime(2026, 3, 15),
    ]);
  });

  test('monatlich am 31. wird auf den letzten Tag gekappt', () {
    final start = DateTime(2026, 1, 31);
    final occ =
        exp(start, const Recurrence(RecurrenceFrequency.monthly, count: 2));
    expect(occ[1], DateTime(2026, 2, 28)); // Februar 2026
  });

  test('jährlich (Geburtstag) erhöht das Jahr', () {
    final start = DateTime(2026, 7, 1);
    final occ =
        exp(start, const Recurrence(RecurrenceFrequency.yearly, count: 2));
    expect(occ, [DateTime(2026, 7, 1), DateTime(2027, 7, 1)]);
  });

  test('UNTIL begrenzt die Serie', () {
    final start = DateTime(2026, 6, 1);
    final occ = exp(
      start,
      Recurrence(RecurrenceFrequency.daily, until: DateTime(2026, 6, 5)),
    );
    expect(occ.last, DateTime(2026, 6, 5));
    expect(occ, hasLength(5));
  });

  test('nur Instanzen im Fenster werden zurückgegeben', () {
    final occ = expander.expand(
      DateTime(2026, 6, 1),
      const Recurrence(RecurrenceFrequency.daily, count: 100),
      windowStart: DateTime(2026, 6, 10),
      windowEnd: DateTime(2026, 6, 12),
    );
    expect(occ, [
      DateTime(2026, 6, 10),
      DateTime(2026, 6, 11),
      DateTime(2026, 6, 12),
    ]);
  });
}
