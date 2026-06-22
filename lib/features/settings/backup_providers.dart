import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBackupFreqKey = 'backup_frequency';
const kBackupLastKey = 'backup_last_ms';

/// Ist eine automatische Sicherung fällig? Reine Funktion (testbar).
/// [freq] = 'none' | 'daily' | 'weekly' | 'monthly'.
bool isBackupDue(String freq, DateTime? last, DateTime now) {
  final days = switch (freq) {
    'daily' => 1,
    'weekly' => 7,
    'monthly' => 30,
    _ => 0,
  };
  if (days == 0) return false;
  if (last == null) return true;
  return !now.isBefore(last.add(Duration(days: days)));
}

/// Auto-Sicherungs-Intervall (persistiert).
final backupFrequencyProvider =
    AsyncNotifierProvider<BackupFrequencyController, String>(
      BackupFrequencyController.new,
    );

class BackupFrequencyController extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kBackupFreqKey) ?? 'weekly';
  }

  Future<void> set(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kBackupFreqKey, value);
    state = AsyncData(value);
  }
}

/// Zeitpunkt der letzten Sicherung (persistiert), `null` = noch keine.
final backupLastProvider =
    AsyncNotifierProvider<BackupLastController, DateTime?>(
      BackupLastController.new,
    );

class BackupLastController extends AsyncNotifier<DateTime?> {
  @override
  Future<DateTime?> build() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(kBackupLastKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> markNow() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    await prefs.setInt(kBackupLastKey, now.millisecondsSinceEpoch);
    state = AsyncData(now);
  }
}
