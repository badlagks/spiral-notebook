import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logic/calculator.dart';
import '../../models/notebook.dart';
import '../store_scope.dart';

/// A desk calculator resting on the page. Click it to type with the keyboard too.
class CalculatorView extends StatefulWidget {
  const CalculatorView({super.key, required this.block});

  final CalculatorBlock block;

  @override
  State<CalculatorView> createState() => _CalculatorViewState();
}

enum _KeyKind { memory, function, operator, digit, equals }

class _CalculatorViewState extends State<CalculatorView> {
  late final _engine = CalculatorEngine(display: widget.block.display, memory: widget.block.memory);
  final _focus = FocusNode(debugLabel: 'calculator');

  static const _rows = [
    ['MC', 'MR', 'M+', 'M−'],
    ['C', '√', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '−'],
    ['1', '2', '3', '+'],
    ['±', '0', '.', '='],
  ];

  static _KeyKind _kindOf(String key) => switch (key) {
        'MC' || 'MR' || 'M+' || 'M−' => _KeyKind.memory,
        'C' || '√' || '%' || '±' => _KeyKind.function,
        '÷' || '×' || '−' || '+' => _KeyKind.operator,
        '=' => _KeyKind.equals,
        _ => _KeyKind.digit,
      };

  static const _keyboard = <String, String>{
    '+': '+', '-': '−', '*': '×', 'x': '×', '/': '÷', '=': '=', '%': '%', '.': '.', ',': '.',
  };

  void _press(String key) {
    setState(() => _engine.press(key));
    widget.block
      ..display = _engine.display
      ..memory = _engine.memory;
    StoreScope.read(context).changedQuietly();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final ch = event.character;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _press('=');
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _press('C');
    } else if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _press(ch);
    } else if (ch != null && _keyboard.containsKey(ch)) {
      _press(_keyboard[ch]!);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: CalculatorBlock.naturalWidth,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: GestureDetector(
          onTapDown: (_) => _focus.requestFocus(),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF1E9D8), Color(0xFFD9CDB4)],
              ),
              border: Border.all(color: const Color(0xFFB8AA8C)),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 12, offset: Offset(3, 6)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _solarStrip(),
                const SizedBox(height: 8),
                _screen(),
                const SizedBox(height: 10),
                for (final row in _rows)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [for (final k in row) _key(k)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _solarStrip() => Container(
        width: 70,
        height: 14,
        decoration: BoxDecoration(
          color: const Color(0xFF4A3B30),
          borderRadius: BorderRadius.circular(2),
          gradient: const LinearGradient(colors: [Color(0xFF5B4636), Color(0xFF3A2C22)]),
        ),
      );

  Widget _screen() => Container(
        width: double.infinity,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFB7C2A4), Color(0xFFCAD4B6)],
          ),
          border: Border.all(color: const Color(0xFF6E7560), width: 2),
        ),
        child: Row(
          children: [
            if (_engine.memory != 0)
              const Text('M', style: TextStyle(fontFamily: 'Roboto', fontSize: 11, color: Color(0xFF2A3024))),
            const Spacer(),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _engine.display,
                  style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                    color: Color(0xFF20261A),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _key(String label) {
    final kind = _kindOf(label);
    final (top, bottom, text) = switch (kind) {
      _KeyKind.memory => (const Color(0xFFE6A99A), const Color(0xFFC77E6C), Colors.white),
      _KeyKind.function => (const Color(0xFF6DC1B3), const Color(0xFF3F978A), Colors.white),
      _KeyKind.operator => (const Color(0xFFF7A54A), const Color(0xFFE07F1F), Colors.white),
      _KeyKind.equals => (const Color(0xFFF7A54A), const Color(0xFFE07F1F), Colors.white),
      _KeyKind.digit => (const Color(0xFF5E7FB5), const Color(0xFF3E5D92), Colors.white),
    };
    return Semantics(
      button: true,
      child: _PressableKey(
        onTap: () => _press(label),
        top: top,
        bottom: bottom,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Roboto',
            fontSize: kind == _KeyKind.memory ? 12 : 18,
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
      ),
    );
  }
}

/// A chunky plastic key that sinks a little when pressed.
class _PressableKey extends StatefulWidget {
  const _PressableKey({required this.onTap, required this.top, required this.bottom, required this.child});

  final VoidCallback onTap;
  final Color top;
  final Color bottom;
  final Widget child;

  @override
  State<_PressableKey> createState() => _PressableKeyState();
}

class _PressableKeyState extends State<_PressableKey> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) {
        setState(() => _down = false);
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: 40,
        height: 32,
        margin: EdgeInsets.only(top: _down ? 2 : 0, bottom: _down ? 0 : 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [widget.top, widget.bottom],
          ),
          boxShadow: _down
              ? const []
              : [BoxShadow(color: widget.bottom.withValues(alpha: 0.9), offset: const Offset(0, 2))],
        ),
        child: widget.child,
      ),
    );
  }
}
