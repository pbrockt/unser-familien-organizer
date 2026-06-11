import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notifications/notification_service.dart';

/// Einstellungen für Erinnerungen.
class NotificationSettings {
  const NotificationSettings({this.enabled = false, this.leadMinutes = 30});

  final bool enabled;
  final int leadMinutes;

  NotificationSettings copyWith({bool? enabled, int? leadMinutes}) =>
      NotificationSettings(
        enabled: enabled ?? this.enabled,
        leadMinutes: leadMinutes ?? this.leadMinutes,
      );
}

/// Singleton des Benachrichtigungs-Dienstes.
final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

/// Persistierte Erinnerungs-Einstellungen.
final notificationSettingsProvider =
    AsyncNotifierProvider<NotificationSettingsController, NotificationSettings>(
  NotificationSettingsController.new,
);

class NotificationSettingsController
    extends AsyncNotifier<NotificationSettings> {
  static const _kEnabled = 'notif_enabled';
  static const _kLead = 'notif_lead_min';

  @override
  Future<NotificationSettings> build() async {
    final prefs = await SharedPreferences.getInstance();
    return NotificationSettings(
      enabled: prefs.getBool(_kEnabled) ?? false,
      leadMinutes: prefs.getInt(_kLead) ?? 30,
    );
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
    final current = state.value ?? const NotificationSettings();
    state = AsyncData(current.copyWith(enabled: value));
  }

  Future<void> setLeadMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLead, minutes);
    final current = state.value ?? const NotificationSettings();
    state = AsyncData(current.copyWith(leadMinutes: minutes));
  }
}
