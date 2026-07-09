import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:family_planner/features/members/member_settings.dart';

CalendarEvent _ev(String href) => CalendarEvent(
  uid: href,
  summary: 'x',
  start: DateTime(2026, 1, 1),
  calendarHref: href,
);

void main() {
  test('applyMemberColors blendet versteckte Kalender NICHT aus', () {
    final events = [_ev('/a'), _ev('/b')];
    const settings = {'/a': MemberSetting(hidden: true, colorHex: '#FF0000')};
    final out = applyMemberColors(events, settings);
    // Beide Termine bleiben erhalten (Startseite ignoriert den Kalender-Filter).
    expect(out.length, 2);
    // Farbe wird trotzdem übernommen.
    expect(
      out.firstWhere((e) => e.calendarHref == '/a').color,
      const Color(0xFFFF0000),
    );
  });

  test('filterVisibleEvents blendet versteckte Kalender weiterhin aus', () {
    final events = [_ev('/a'), _ev('/b')];
    const settings = {'/a': MemberSetting(hidden: true)};
    final out = filterVisibleEvents(events, settings);
    expect(out.length, 1);
    expect(out.single.calendarHref, '/b');
  });
}
