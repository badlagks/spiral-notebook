import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'alarms.dart';

Alarms platformAlarms() => _BrowserAlarms();

/// In a browser, reminders ring only while the notebook is open in a tab:
/// a soft two-note chime and, if allowed, a browser notification.
class _BrowserAlarms implements Alarms {
  @override
  bool get ringsWhenClosed => false;

  @override
  Future<void> init() async {}

  @override
  Future<bool> askPermission() async {
    try {
      if (web.Notification.permission == 'granted') return true;
      final result = await web.Notification.requestPermission().toDart;
      return result.toDart == 'granted';
    } catch (e) {
      debugPrint('Browser notifications unavailable: $e');
      return false;
    }
  }

  @override
  Future<void> schedule(int id, DateTime at, String title, String body) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> ring(String title, String body) async {
    _chime();
    try {
      if (web.Notification.permission == 'granted') {
        web.Notification(title, web.NotificationOptions(body: body));
      }
    } catch (e) {
      debugPrint('Could not show a browser notification: $e');
    }
  }

  void _chime() {
    try {
      final ctx = web.AudioContext();
      final start = ctx.currentTime;
      for (final (i, freq) in [880.0, 1318.5].indexed) {
        final osc = ctx.createOscillator()
          ..type = 'sine'
          ..frequency.value = freq;
        final gain = ctx.createGain();
        final t = start + i * 0.28;
        gain.gain
          ..setValueAtTime(0.0001, t)
          ..exponentialRampToValueAtTime(0.25, t + 0.02)
          ..exponentialRampToValueAtTime(0.0001, t + 0.9);
        osc
          ..connect(gain)
          ..start(t)
          ..stop(t + 1.0);
        gain.connect(ctx.destination);
      }
    } catch (e) {
      debugPrint('Could not play the chime: $e');
    }
  }
}
