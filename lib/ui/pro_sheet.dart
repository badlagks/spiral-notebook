import 'dart:async';

import 'package:flutter/material.dart';

import '../data/pro.dart';

/// Returns true at once if Pro is unlocked. Otherwise explains what Pro adds,
/// starting with [reason], and offers to unlock it. Returns true if it is
/// unlocked by the time the sheet closes.
Future<bool> requirePro(BuildContext context, {required String reason}) async {
  if (purchases.isPro.value) return true;
  await showProSheet(context, reason: reason);
  return purchases.isPro.value;
}

/// What Pro adds, with buttons to unlock it or restore an earlier purchase.
Future<void> showProSheet(BuildContext context, {String? reason}) =>
    showDialog<void>(context: context, builder: (_) => _ProSheet(reason: reason));

class _ProSheet extends StatefulWidget {
  const _ProSheet({this.reason});
  final String? reason;

  @override
  State<_ProSheet> createState() => _ProSheetState();
}

class _ProSheetState extends State<_ProSheet> {
  String? _price;
  bool _loading = true;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    purchases.isPro.addListener(_onPro);
    purchases.price().then((p) {
      if (mounted) {
        setState(() {
          _price = p;
          _loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    purchases.isPro.removeListener(_onPro);
    super.dispose();
  }

  void _onPro() {
    if (purchases.isPro.value && mounted) setState(() => _busy = false);
  }

  Future<void> _buy() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final started = await purchases.buy();
    if (!mounted) return;
    if (!started) {
      setState(() {
        _busy = false;
        _message = "The store can't be reached right now. Try again later.";
      });
    } else if (!purchases.isPro.value) {
      // The store's own sheet takes it from here; if it's closed without
      // paying, the button comes back.
      unawaited(Future<void>.delayed(const Duration(seconds: 4), () => mounted ? setState(() => _busy = false) : null));
    }
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await purchases.restore();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = !ok
          ? "The store can't be reached right now. Try again later."
          : purchases.isPro.value
          ? null
          : 'Asked the store. If Pro was bought with this account, it unlocks in a moment.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final pro = purchases.isPro.value;
    return AlertDialog(
      icon: Icon(pro ? Icons.verified : Icons.auto_stories, size: 36, color: const Color(0xFF8B5A1B)),
      title: Text(pro ? 'Pro is unlocked' : 'Spiral Notebook Pro'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pro)
              const Text('Thank you! Make as many notebooks as you like, each with its own cover.')
            else ...[
              if (widget.reason != null) ...[
                Text(widget.reason!, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
              ],
              const _Point(Icons.collections_bookmark_outlined, 'As many notebooks as you like'),
              const _Point(Icons.palette_outlined, 'A cover colour for each one'),
              const _Point(Icons.payments_outlined, 'Pay once. No subscription, no account'),
              const SizedBox(height: 8),
              const Text(
                'Everything else is free in your first notebook, and stays that way.',
                style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!, style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: pro
          ? [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))]
          : [
              TextButton(onPressed: _busy ? null : _restore, child: const Text('Restore purchase')),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not now')),
              FilledButton(
                onPressed: _busy || _loading ? null : _buy,
                child: _busy || _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_price == null ? 'Unlock Pro' : 'Unlock for $_price'),
              ),
            ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF8B5A1B)),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
