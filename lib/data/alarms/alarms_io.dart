import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'alarms.dart';

Alarms platformAlarms() => _DeviceAlarms();

/// Notifications from the phone or Mac itself, so reminders ring with the
/// notebook closed. They make their own sound.
class _DeviceAlarms implements Alarms {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Reminders you set on your notebook pages',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
    macOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
  );

  @override
  bool get ringsWhenClosed => _supported;

  @override
  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (e) {
      debugPrint('Could not read the time zone, using UTC: $e');
    }
    try {
      // Permission is asked for when the first reminder is set, not at launch.
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifications are not available: $e');
    }
  }

  @override
  Future<bool> askPermission() async {
    await init();
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
      final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
      if (mac != null) return await mac.requestPermissions(alert: true, sound: true) ?? false;
    } catch (e) {
      debugPrint('Could not ask for notifications: $e');
    }
    return false;
  }

  @override
  Future<void> schedule(int id, DateTime at, String title, String body) async {
    await init();
    if (!_ready) return;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      // On time to the minute when Android allows it, otherwise within a few minutes.
      final exact = await android?.canScheduleExactNotifications() ?? true;
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
    } catch (e) {
      debugPrint('Could not set reminder: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('Could not cancel reminder: $e');
    }
  }

  @override
  Future<void> ring(String title, String body) async {
    // The device's own notification plays the sound. Elsewhere, a beep.
    if (!_ready) await SystemSound.play(SystemSoundType.alert);
  }
}
