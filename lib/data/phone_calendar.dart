import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:flutter/foundation.dart';

/// An event from the phone's own calendar (Apple or Google), shown read-only.
class PhoneEvent {
  const PhoneEvent({required this.title, required this.start, required this.end, required this.allDay});
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
}

/// The calendar app on the phone. Everything stays on the device: the
/// notebook reads it and adds to it there, never through the internet.
abstract class PhoneCalendar {
  /// Only phones have one the notebook can reach.
  bool get available;

  /// Asks once for permission. True if allowed.
  Future<bool> askPermission();

  Future<List<PhoneEvent>> events(DateTime from, DateTime to);

  /// Adds a short event at [at] with an alert, returning its id.
  Future<String?> add(String title, DateTime at, String note);

  Future<void> remove(String id);
}

class _DevicePhoneCalendar implements PhoneCalendar {
  DeviceCalendar get _cal => DeviceCalendar.instance;

  @override
  bool get available =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<bool> askPermission() async {
    if (!available) return false;
    try {
      return await _cal.requestPermissions() == CalendarPermissionStatus.granted;
    } catch (e) {
      debugPrint('Calendar permission failed: $e');
      return false;
    }
  }

  @override
  Future<List<PhoneEvent>> events(DateTime from, DateTime to) async {
    if (!available) return [];
    try {
      if (await _cal.hasPermissions() != CalendarPermissionStatus.granted) return [];
      final list = await _cal.listEvents(from, to);
      return [for (final e in list) PhoneEvent(title: e.title, start: e.startDate, end: e.endDate, allDay: e.isAllDay)];
    } catch (e) {
      debugPrint('Could not read the calendar: $e');
      return [];
    }
  }

  @override
  Future<String?> add(String title, DateTime at, String note) async {
    if (!await askPermission()) return null;
    try {
      return await _cal.createEvent(
        title: title,
        startDate: at,
        endDate: at.add(const Duration(minutes: 30)),
        description: note,
        reminders: const [Duration.zero],
      );
    } catch (e) {
      debugPrint('Could not add to the calendar: $e');
      return null;
    }
  }

  @override
  Future<void> remove(String id) async {
    if (!available) return;
    try {
      await _cal.deleteEvent(instanceId: id);
    } catch (e) {
      debugPrint('Could not remove the calendar event: $e');
    }
  }
}

PhoneCalendar phoneCalendar = _DevicePhoneCalendar();
