import 'dart:math' as math;

import 'formula.dart';

/// A pocket calculator that works like the real thing: each operator
/// applies to the running total as you go (12 + 3 × 2 = 30).
class CalculatorEngine {
  CalculatorEngine({String display = '0', this.memory = 0}) : _entry = display.replaceAll(',', '');

  String _entry;
  double? _accumulator;
  String? _pendingOp;
  bool _startNewEntry = true;
  double memory;

  /// What the calculator screen shows.
  String get display {
    if (_entry == 'Error') return _entry;
    final n = double.tryParse(_entry);
    if (n == null) return _entry;
    // Keep a trailing "." or trailing zeros while the person is typing.
    if (_entry.contains('.')) {
      final parts = _entry.split('.');
      final whole = formatNumber(double.parse(parts[0].isEmpty || parts[0] == '-' ? '0' : parts[0]));
      final sign = _entry.startsWith('-') && !whole.startsWith('-') ? '-' : '';
      return '$sign$whole.${parts[1]}';
    }
    return formatNumber(n);
  }

  double get _value => double.tryParse(_entry) ?? 0;

  void press(String key) {
    if (_entry == 'Error' && key != 'C') return;
    switch (key) {
      case '0' || '1' || '2' || '3' || '4' || '5' || '6' || '7' || '8' || '9':
        if (_startNewEntry || _entry == '0') {
          _entry = key;
        } else if (_entry.replaceAll(RegExp(r'[-.]'), '').length < 12) {
          _entry += key;
        }
        _startNewEntry = false;
      case '.':
        if (_startNewEntry) {
          _entry = '0.';
        } else if (!_entry.contains('.')) {
          _entry += '.';
        }
        _startNewEntry = false;
      case '+' || '−' || '×' || '÷':
        if (_pendingOp != null && !_startNewEntry) {
          _apply();
        } else {
          _accumulator = _value;
        }
        _pendingOp = key;
        _startNewEntry = true;
      case '=':
        if (_pendingOp != null) _apply();
        _pendingOp = null;
        _startNewEntry = true;
      case 'C':
        _entry = '0';
        _accumulator = null;
        _pendingOp = null;
        _startNewEntry = true;
      case '±':
        if (_entry != '0') {
          _entry = _entry.startsWith('-') ? _entry.substring(1) : '-$_entry';
        }
      case '%':
        // Like a desk calculator: 200 + 10% → 200 + 20.
        final base = (_pendingOp == '+' || _pendingOp == '−') ? (_accumulator ?? 0) : 1;
        _setResult(_value / 100 * base);
      case '√':
        if (_value < 0) {
          _entry = 'Error';
        } else {
          _setResult(math.sqrt(_value));
        }
      case 'MC':
        memory = 0;
      case 'MR':
        _setResult(memory);
      case 'M+':
        memory += _value;
        _startNewEntry = true;
      case 'M−':
        memory -= _value;
        _startNewEntry = true;
    }
  }

  void _apply() {
    final a = _accumulator ?? 0;
    final b = _value;
    double result;
    switch (_pendingOp) {
      case '+':
        result = a + b;
      case '−':
        result = a - b;
      case '×':
        result = a * b;
      case '÷':
        if (b == 0) {
          _entry = 'Error';
          _accumulator = null;
          _pendingOp = null;
          return;
        }
        result = a / b;
      default:
        result = b;
    }
    _accumulator = result;
    _setResult(result);
  }

  void _setResult(double v) {
    if (v.isNaN || v.isInfinite) {
      _entry = 'Error';
    } else {
      // Round away floating point noise like 0.1 + 0.2.
      final rounded = double.parse(v.toStringAsPrecision(12));
      _entry = rounded == rounded.roundToDouble() && rounded.abs() < 1e15
          ? rounded.toStringAsFixed(0)
          : rounded.toString();
    }
    _startNewEntry = true;
  }
}
