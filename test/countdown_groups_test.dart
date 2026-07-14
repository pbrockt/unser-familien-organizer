import 'package:family_planner/core/caldav/http_caldav_client.dart';
import 'package:family_planner/features/calendar/calendar_event.dart';
import 'package:family_planner/features/members/member_settings.dart';
import 'package:family_planner/features/members/user_groups.dart';
import 'package:flutter_test/flutter_test.dart';

CalendarEvent _ev(String summary, DateTime start, DateTime endExcl) =>
    CalendarEvent(
      uid: summary,
      summary: summary,
      start: start,
      end: endExcl,
      allDay: true,
      calendarHref: '/c/ferien',
    );

void main() {
  group('countdownEvents – laufende Termine', () {
    final today = DateTime(2026, 7, 9);
    const settings = {'/c/ferien': MemberSetting(countdown: true)};
    // Sommerferien laufen (1.7.–31.8.), Herbstferien künftig (20.10.).
    final sommer = _ev(
      'Sommerferien',
      DateTime(2026, 7, 1),
      DateTime(2026, 9, 1),
    );
    final herbst = _ev(
      'Herbstferien',
      DateTime(2026, 10, 20),
      DateTime(2026, 11, 1),
    );
    // Vergangen (endet vor heute).
    final ostern = _ev(
      'Osterferien',
      DateTime(2026, 6, 1),
      DateTime(2026, 6, 15),
    );

    test('nur der nächste: laufender Termin gewinnt', () {
      final out = countdownEvents([herbst, sommer, ostern], settings, today);
      expect(out, hasLength(1));
      expect(out.single.summary, 'Sommerferien');
    });

    test('alle: laufend + künftig, vergangene raus, nach Start sortiert', () {
      const all = {
        '/c/ferien': MemberSetting(countdown: true, countdownAll: true),
      };
      final out = countdownEvents([herbst, sommer, ostern], all, today);
      expect(out.map((e) => e.summary), ['Sommerferien', 'Herbstferien']);
    });

    test('heute bereits beendeter Termin fällt raus, nächster gewinnt', () {
      const s = {'/c/a': MemberSetting(countdown: true)};
      CalendarEvent timed(String name, DateTime start, DateTime end) =>
          CalendarEvent(
            uid: name,
            summary: name,
            start: start,
            end: end,
            calendarHref: '/c/a',
          );
      final heute = timed(
        'Arbeit',
        DateTime(2026, 7, 9, 18),
        DateTime(2026, 7, 9, 20),
      );
      final morgen = timed(
        'Termin morgen',
        DateTime(2026, 7, 10, 9),
        DateTime(2026, 7, 10, 10),
      );
      // Es ist 21:00 – der heutige Termin (endet 20:00) ist vorbei.
      final out = countdownEvents([heute, morgen], s, DateTime(2026, 7, 9, 21));
      expect(out.single.summary, 'Termin morgen');
    });
  });

  test('parseUserGroups liest Gruppen-IDs aus group-membership', () {
    const body = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
 <d:response>
  <d:href>/remote.php/dav/principals/users/vincent/</d:href>
  <d:propstat>
   <d:prop>
    <d:group-membership>
     <d:href>/remote.php/dav/principals/groups/Eltern/</d:href>
     <d:href>/remote.php/dav/principals/groups/Familie/</d:href>
    </d:group-membership>
   </d:prop>
   <d:status>HTTP/1.1 200 OK</d:status>
  </d:propstat>
 </d:response>
</d:multistatus>''';
    expect(parseUserGroups(body), ['Eltern', 'Familie']);
    expect(parseUserGroups('<d:multistatus xmlns:d="DAV:"/>'), isEmpty);
  });

  test('isParentByGroups: Auto-Erkennung & explizite Wahl', () {
    // Auto: Gruppenname enthält „eltern".
    expect(
      isParentByGroups(groups: ['Eltern', 'Familie'], selected: null),
      isTrue,
    );
    expect(isParentByGroups(groups: ['Familie'], selected: null), isFalse);
    // Explizit gewählte Gruppe.
    expect(isParentByGroups(groups: ['Team-A'], selected: 'Team-A'), isTrue);
    expect(isParentByGroups(groups: ['Team-A'], selected: 'Team-B'), isFalse);
  });
}
