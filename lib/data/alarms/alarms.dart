import 'alarms_io.dart' if (dart.library.js_interop) 'alarms_web.dart' as impl;

/// Rings reminders: the phone or computer's own notifications where there
/// are some, and a chime with a note while the notebook is open.
abstract class Alarms {
  /// Whether reminders still ring when the notebook isn't open.
  bool get ringsWhenClosed;

  Future<void> init();

  /// Asks once for permission to show notifications. True if allowed.
  Future<bool> askPermission();

  /// Sets the device's alarm [id] to go off at [at]. Replaces any earlier one.
  Future<void> schedule(int id, DateTime at, String title, String body);

  Future<void> cancel(int id);

  /// Plays the reminder sound now, for a reminder due while the notebook is open.
  Future<void> ring(String title, String body);
}

/// A silent stand-in, for tests.
class QuietAlarms implements Alarms {
  final scheduled = <int, DateTime>{};
  final rung = <String>[];

  @override
  bool get ringsWhenClosed => true;

  @override
  Future<void> init() async {}

  @override
  Future<bool> askPermission() async => true;

  @override
  Future<void> schedule(int id, DateTime at, String title, String body) async => scheduled[id] = at;

  @override
  Future<void> cancel(int id) async => scheduled.remove(id);

  @override
  Future<void> ring(String title, String body) async => rung.add(body);
}

Alarms alarms = impl.platformAlarms();
