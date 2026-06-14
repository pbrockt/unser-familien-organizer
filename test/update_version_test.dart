import 'package:flutter_test/flutter_test.dart';
import 'package:family_planner/core/update/update_service.dart';

void main() {
  group('isNewerVersion', () {
    test('erkennt neuere Patch-Version', () {
      expect(isNewerVersion('0.30.4', '0.30.3'), isTrue);
    });

    test('ignoriert Build-Suffix der laufenden Version', () {
      expect(isNewerVersion('0.30.4', '0.30.4+34'), isFalse);
      expect(isNewerVersion('0.30.5', '0.30.4+34'), isTrue);
    });

    test('ignoriert führendes v im Tag', () {
      expect(isNewerVersion('v0.31.0', '0.30.9'), isTrue);
    });

    test('gleiche Version ist nicht neuer', () {
      expect(isNewerVersion('0.30.4', '0.30.4'), isFalse);
    });

    test('ältere Version ist nicht neuer', () {
      expect(isNewerVersion('0.30.2', '0.30.4'), isFalse);
    });

    test('Minor- und Major-Sprünge', () {
      expect(isNewerVersion('0.31.0', '0.30.99'), isTrue);
      expect(isNewerVersion('1.0.0', '0.99.99'), isTrue);
    });
  });
}
