import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../models/notebook.dart';
import 'store_scope.dart';
import 'theme.dart';

/// Checks a face or fingerprint on the device. Swapped in tests.
abstract class DeviceUnlock {
  Future<bool> available();
  Future<bool> check(String reason);
}

class _LocalAuthUnlock implements DeviceUnlock {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() => _available().timeout(const Duration(seconds: 2), onTimeout: () => false);

  Future<bool> _available() async {
    // Browsers have no face or fingerprint check for us.
    if (kIsWeb) return false;
    try {
      final has = await _auth.canCheckBiometrics && (await _auth.getAvailableBiometrics()).isNotEmpty;
      return has;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> check(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (e) {
      debugPrint('Face or fingerprint check failed: $e');
      return false;
    }
  }
}

DeviceUnlock deviceUnlock = _LocalAuthUnlock();

/// True while the device's own face or fingerprint prompt is showing, so the
/// app doesn't lock itself again because that prompt covered it.
bool deviceCheckShowing = false;

/// Asks for the PIN (or a face or fingerprint) and opens [section].
Future<bool> unlockSection(BuildContext context, Section section) async {
  final store = StoreScope.read(context);
  if (!store.isLocked(section)) return true;
  final canUseDevice = await deviceUnlock.available();
  if (!context.mounted) return false;
  final pin = TextEditingController();
  String? error;

  Future<void> useDevice(BuildContext c) async {
    deviceCheckShowing = true;
    final ok = await deviceUnlock.check('Open "${section.name}"');
    deviceCheckShowing = false;
    if (ok) {
      store.unlockTrusted(section);
      if (c.mounted) Navigator.pop(c, true);
    }
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialog) {
        void submit() {
          if (store.unlock(section, pin.text)) {
            Navigator.pop(c, true);
          } else {
            setDialog(() => error = 'That PIN is not right. Try again.');
            pin.clear();
          }
        }

        return AlertDialog(
          icon: const Icon(Icons.lock_outline),
          title: Text('Open "${section.name}"'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PinField(controller: pin, label: 'PIN', error: error, onSubmitted: submit),
                if (canUseDevice) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () => useDevice(c),
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Use face or fingerprint'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Open')),
          ],
        );
      },
    ),
  );
  return ok == true;
}

/// Asks for a new PIN twice. Returns null if cancelled.
Future<String?> askNewPin(BuildContext context, {required String title}) async {
  final first = TextEditingController();
  final second = TextEditingController();
  String? error;
  final pin = await showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setDialog) {
        void submit() {
          if (first.text.length < 4) {
            setDialog(() => error = 'Use at least 4 numbers.');
          } else if (first.text != second.text) {
            setDialog(() => error = 'The two PINs are different.');
            second.clear();
          } else {
            Navigator.pop(c, first.text);
          }
        }

        return AlertDialog(
          icon: const Icon(Icons.lock_outline),
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PinField(controller: first, label: 'New PIN', onSubmitted: submit),
                const SizedBox(height: 8),
                _PinField(
                  controller: second,
                  label: 'Same PIN again',
                  error: error,
                  onSubmitted: submit,
                  autofocus: false,
                ),
                const SizedBox(height: 12),
                const Text(
                  'The section stays hidden until someone types this PIN. '
                  'If it is forgotten, the section cannot be opened, so pick one you will remember.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Lock it')),
          ],
        );
      },
    ),
  );
  return pin;
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.label,
    required this.onSubmitted,
    this.error,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final String label;
  final String? error;
  final VoidCallback onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    autofocus: autofocus,
    obscureText: true,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
    decoration: InputDecoration(labelText: label, errorText: error),
    // Keeps the keyboard up after a wrong PIN, ready for another try.
    onEditingComplete: () {},
    onSubmitted: (_) => onSubmitted(),
  );
}

/// Shown in place of a locked section's pages.
class LockedSheet extends StatelessWidget {
  const LockedSheet({super.key, required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Paper.sheet),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: Color(section.color)),
            const SizedBox(height: 14),
            Text(section.name, style: headingHandwriting.copyWith(fontSize: 32)),
            const SizedBox(height: 6),
            Text('This section is locked.', style: handwriting.copyWith(color: Pen.pencil)),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => unlockSection(context, section),
              icon: const Icon(Icons.lock_open),
              label: const Text('Unlock'),
            ),
          ],
        ),
      ),
    );
  }
}
