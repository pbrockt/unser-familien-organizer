import 'package:family_planner/core/backup/backup_service.dart';
import 'package:family_planner/features/settings/backup_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isBackupDue', () {
    final now = DateTime(2026, 6, 22, 9);
    test('„none" nie fällig', () {
      expect(isBackupDue('none', null, now), isFalse);
      expect(isBackupDue('none', now.subtract(const Duration(days: 99)), now),
          isFalse);
    });
    test('ohne letzte Sicherung sofort fällig', () {
      expect(isBackupDue('weekly', null, now), isTrue);
    });
    test('wöchentlich erst nach 7 Tagen', () {
      expect(isBackupDue('weekly', now.subtract(const Duration(days: 6)), now),
          isFalse);
      expect(isBackupDue('weekly', now.subtract(const Duration(days: 7)), now),
          isTrue);
    });
    test('täglich nach 1 Tag', () {
      expect(isBackupDue('daily', now.subtract(const Duration(hours: 23)), now),
          isFalse);
      expect(isBackupDue('daily', now.subtract(const Duration(days: 1)), now),
          isTrue);
    });
  });

  group('build/apply round-trip', () {
    test('Prefs werden gesichert und wiederhergestellt', () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode': 'dark',
        'upcoming_days': 3,
        'templates_enabled': false,
        'event_templates': '[{"summary":"Sport"}]',
      });
      final backup = await BackupService.buildBackupMap();
      expect(backup['prefs'], containsPair('theme_mode', 'dark'));
      expect(backup['prefs'], containsPair('upcoming_days', 3));

      // Werte verändern …
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
      // … dann aus der Sicherung wiederherstellen.
      await BackupService.applyBackupMap(backup);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');
      expect(prefs.getInt('upcoming_days'), 3);
      expect(prefs.getBool('templates_enabled'), false);
      expect(prefs.getString('event_templates'), '[{"summary":"Sport"}]');
    });
  });
}
