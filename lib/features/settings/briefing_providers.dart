import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBriefingEnabledKey = 'briefing_enabled';
const kBriefingTimeKey = 'briefing_time_min'; // Minuten ab Mitternacht

/// Einstellungen für das tägliche Morgen-Briefing.
class BriefingSettings {
  const BriefingSettings({this.enabled = false, this.minutesOfDay = 7 * 60});
  final bool enabled;
  final int minutesOfDay;

  int get hour => minutesOfDay ~/ 60;
  int get minute => minutesOfDay % 60;

  BriefingSettings copyWith({bool? enabled, int? minutesOfDay}) =>
      BriefingSettings(
        enabled: enabled ?? this.enabled,
        minutesOfDay: minutesOfDay ?? this.minutesOfDay,
      );
}

final briefingSettingsProvider =
    AsyncNotifierProvider<BriefingController, BriefingSettings>(
      BriefingController.new,
    );

class BriefingController extends AsyncNotifier<BriefingSettings> {
  @override
  Future<BriefingSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return BriefingSettings(
      enabled: prefs.getBool(kBriefingEnabledKey) ?? false,
      minutesOfDay: prefs.getInt(kBriefingTimeKey) ?? 7 * 60,
    );
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBriefingEnabledKey, value);
    state = AsyncData(
      (state.value ?? const BriefingSettings()).copyWith(enabled: value),
    );
  }

  Future<void> setTime(int minutesOfDay) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kBriefingTimeKey, minutesOfDay);
    state = AsyncData(
      (state.value ?? const BriefingSettings()).copyWith(
        minutesOfDay: minutesOfDay,
      ),
    );
  }
}
