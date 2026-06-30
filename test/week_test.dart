import 'package:family_planner/shared/utils/week.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ISO-Kalenderwoche – bekannte Daten', () {
    expect(isoWeekNumber(DateTime(2026, 1, 1)), 1); // Do → KW 1
    expect(isoWeekNumber(DateTime(2026, 6, 29)), 27); // Montag KW 27
    expect(isoWeekNumber(DateTime(2026, 12, 31)), 53);
    // Jahreswechsel: 1.1.2023 ist Sonntag → noch KW 52 (von 2022).
    expect(isoWeekNumber(DateTime(2023, 1, 1)), 52);
    // 4. Januar liegt immer in KW 1.
    expect(isoWeekNumber(DateTime(2027, 1, 4)), 1);
  });
}
