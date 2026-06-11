import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Eine geplante Erinnerung (entkoppelt von App-Modellen).
class ScheduledReminder {
  const ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.when,
  });

  final int id;
  final String title;
  final String body;
  final DateTime when;
}

/// Kapselt lokale Benachrichtigungen (flutter_local_notifications) inkl.
/// Zeitzonen-Setup und Android-Kanal.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  static const _channelId = 'reminders';

  Future<void> init() async {
    if (_inited) return;

    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      // Fallback: UTC (besser als Absturz).
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );

    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Erinnerungen',
        description: 'Erinnerungen an Termine und Aufgaben',
        importance: Importance.high,
      ),
    );
    _inited = true;
  }

  /// Fragt die Benachrichtigungs-Berechtigung an (Android 13+).
  Future<bool> requestPermission() async {
    await init();
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final granted = await androidImpl?.requestNotificationsPermission();
    return granted ?? false;
  }

  Future<bool> areNotificationsEnabled() async {
    await init();
    final androidImpl =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await androidImpl?.areNotificationsEnabled() ?? false;
  }

  /// Ersetzt alle geplanten Erinnerungen durch [reminders] (nur Zukunft).
  Future<void> schedule(List<ScheduledReminder> reminders) async {
    await init();
    await _plugin.cancelAll();

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Erinnerungen',
        channelDescription: 'Erinnerungen an Termine und Aufgaben',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    final now = DateTime.now();
    for (final r in reminders) {
      if (!r.when.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        scheduledDate: tz.TZDateTime.from(r.when, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// Sofortige Test-Benachrichtigung (zum Prüfen der Berechtigung).
  Future<void> showTest() async {
    await init();
    await _plugin.show(
      id: 999999,
      title: 'FamilyPlanner',
      body: 'Benachrichtigungen funktionieren ✓',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Erinnerungen',
          channelDescription: 'Erinnerungen an Termine und Aufgaben',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
