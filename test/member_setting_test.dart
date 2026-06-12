import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/features/members/member_settings.dart';

void main() {
  test('MemberSetting JSON-Roundtrip', () {
    const s = MemberSetting(name: 'Anna', colorHex: '#42A5F5', hidden: true);
    final back = MemberSetting.fromJson(s.toJson());
    expect(back.name, 'Anna');
    expect(back.colorHex, '#42A5F5');
    expect(back.hidden, isTrue);
  });

  test('copyWith mit clearColor entfernt die Farbe', () {
    const s = MemberSetting(colorHex: '#FF0000');
    expect(s.copyWith(clearColor: true).colorHex, isNull);
  });

  test('copyWith ändert nur das Angegebene', () {
    const s = MemberSetting(name: 'A', colorHex: '#111111');
    final r = s.copyWith(hidden: true);
    expect(r.name, 'A');
    expect(r.colorHex, '#111111');
    expect(r.hidden, isTrue);
  });
}
