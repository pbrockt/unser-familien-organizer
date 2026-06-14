import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:family_planner/features/calendar/day_timeline.dart';

CalendarEvent _ev(String id, DateTime start, DateTime? end,
        {bool allDay = false}) =>
    CalendarEvent(
        uid: id, summary: id, start: start, end: end, allDay: allDay);

void main() {
  final day = DateTime(2026, 6, 14);
  DateTime at(int h, int m) => DateTime(2026, 6, 14, h, m);

  group('layoutDayEvents', () {
    test('nicht überlappende Termine: je eine Spalte', () {
      final res = layoutDayEvents([
        _ev('A', at(9, 0), at(10, 0)),
        _ev('B', at(11, 0), at(12, 0)),
      ], day);
      expect(res.length, 2);
      for (final p in res) {
        expect(p.columns, 1);
        expect(p.column, 0);
      }
      final a = res.firstWhere((p) => p.event.uid == 'A');
      expect(a.startMinute, 540);
      expect(a.endMinute, 600);
    });

    test('überlappende Termine: zwei Spalten', () {
      final res = layoutDayEvents([
        _ev('A', at(9, 0), at(10, 0)),
        _ev('B', at(9, 30), at(10, 30)),
      ], day);
      expect(res.length, 2);
      expect(res.every((p) => p.columns == 2), isTrue);
      expect(res.map((p) => p.column).toSet(), {0, 1});
    });

    test('ohne Ende: Standarddauer 60 Minuten', () {
      final res = layoutDayEvents([_ev('C', at(14, 0), null)], day);
      expect(res.single.endMinute - res.single.startMinute, 60);
    });

    test('ganztägige Termine werden nicht im Raster platziert', () {
      final res = layoutDayEvents([
        _ev('G', day, day.add(const Duration(days: 1)), allDay: true),
        _ev('A', at(9, 0), at(10, 0)),
      ], day);
      expect(res.length, 1);
      expect(res.single.event.uid, 'A');
    });

    test('drei sich überlappende Termine: drei Spalten', () {
      final res = layoutDayEvents([
        _ev('A', at(9, 0), at(11, 0)),
        _ev('B', at(9, 30), at(10, 30)),
        _ev('C', at(9, 45), at(10, 15)),
      ], day);
      expect(res.every((p) => p.columns == 3), isTrue);
      expect(res.map((p) => p.column).toSet(), {0, 1, 2});
    });
  });
}
