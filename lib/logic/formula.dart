import 'dart:math' as math;

/// Result of evaluating one spreadsheet cell.
class CellValue {
  const CellValue.number(this.number, {this.currency = false}) : error = null, text = null;
  const CellValue.text(this.text) : number = null, currency = false, error = null;
  const CellValue.error(this.error) : number = null, currency = false, text = null;
  static const empty = CellValue.text('');

  final double? number;
  final String? text;
  final String? error;

  /// True when the value came from (or was computed from) "$" amounts,
  /// so it should be shown as money.
  final bool currency;

  String get display {
    if (error != null) return error!;
    if (number != null) return formatNumber(number!, currency: currency);
    return text ?? '';
  }
}

String formatNumber(double n, {bool currency = false}) {
  if (n.isNaN || n.isInfinite) return '#NUM!';
  if (currency) {
    final neg = n < 0;
    return '${neg ? '-' : ''}\$${_groupThousands(n.abs().toStringAsFixed(2))}';
  }
  if (n == n.roundToDouble() && n.abs() < 1e15) {
    return _groupThousands(n.toStringAsFixed(0));
  }
  var s = n.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return _groupThousands(s);
}

String _groupThousands(String s) {
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final parts = s.split('.');
  final buf = StringBuffer();
  final whole = parts[0];
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  if (parts.length > 1) buf.write('.${parts[1]}');
  return '${neg ? '-' : ''}$buf';
}

/// Parses things people type into a cell as numbers: "12", "$10.00", "1,450", "-3.5".
double? parseLooseNumber(String raw) {
  final s = raw.trim().replaceAll(',', '').replaceAll('\$', '');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Column letters for a zero-based index: 0 → A, 25 → Z, 26 → AA.
String columnName(int index) {
  var n = index + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

int _columnIndex(String letters) {
  var n = 0;
  for (final c in letters.codeUnits) {
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

/// Evaluates every cell of a sheet. Supports numbers, cell references (B2),
/// ranges inside functions (SUM(D2:D8)), + - * / ^, parentheses, and
/// SUM, AVG/AVERAGE, MIN, MAX, COUNT.
class SheetEvaluator {
  SheetEvaluator(this.cells);

  final List<List<String>> cells;
  final Map<(int, int), CellValue> _cache = {};
  final Set<(int, int)> _visiting = {};

  CellValue valueAt(int row, int col) {
    final key = (row, col);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (row < 0 || row >= cells.length || col < 0 || col >= cells[row].length) {
      return CellValue.empty;
    }
    if (_visiting.contains(key)) return const CellValue.error('#CYCLE!');
    _visiting.add(key);
    final v = _evaluateRaw(cells[row][col]);
    _visiting.remove(key);
    _cache[key] = v;
    return v;
  }

  CellValue _evaluateRaw(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('=')) {
      try {
        final parser = _Parser(trimmed.substring(1), this);
        final result = parser.parse();
        return CellValue.number(result.value, currency: result.currency);
      } on _FormulaError catch (e) {
        return CellValue.error(e.code);
      }
    }
    final n = parseLooseNumber(trimmed);
    if (n != null) return CellValue.number(n, currency: trimmed.contains('\$'));
    return CellValue.text(raw);
  }
}

class _FormulaError implements Exception {
  _FormulaError(this.code);
  final String code;
}

class _Num {
  const _Num(this.value, this.currency);
  final double value;
  final bool currency;
}

final _tokenPattern = RegExp(
    r'\s*(?:(\d+(?:\.\d*)?|\.\d+)|([A-Za-z]+\d+)(?::([A-Za-z]+\d+))?|([A-Za-z]+)|(.))');
final _refPattern = RegExp(r'^([A-Za-z]+)(\d+)$');

class _Parser {
  _Parser(String source, this.sheet) {
    for (final m in _tokenPattern.allMatches(source)) {
      if (m.group(0)!.trim().isEmpty) continue;
      _tokens.add(m);
    }
  }

  final SheetEvaluator sheet;
  final List<RegExpMatch> _tokens = [];
  int _pos = 0;

  RegExpMatch? get _peek => _pos < _tokens.length ? _tokens[_pos] : null;
  String? get _peekSymbol => _peek?.group(5);

  _Num parse() {
    final v = _expression();
    if (_peek != null) throw _FormulaError('#ERROR!');
    return v;
  }

  _Num _expression() {
    var left = _term();
    while (_peekSymbol == '+' || _peekSymbol == '-') {
      final op = _tokens[_pos++].group(5);
      final right = _term();
      left = _Num(op == '+' ? left.value + right.value : left.value - right.value,
          left.currency || right.currency);
    }
    return left;
  }

  _Num _term() {
    var left = _power();
    while (_peekSymbol == '*' || _peekSymbol == '/') {
      final op = _tokens[_pos++].group(5);
      final right = _power();
      if (op == '/' && right.value == 0) throw _FormulaError('#DIV/0!');
      left = _Num(op == '*' ? left.value * right.value : left.value / right.value,
          left.currency || right.currency);
    }
    return left;
  }

  _Num _power() {
    final base = _unary();
    if (_peekSymbol == '^') {
      _pos++;
      final exp = _power();
      return _Num(math.pow(base.value, exp.value).toDouble(), base.currency);
    }
    return base;
  }

  _Num _unary() {
    if (_peekSymbol == '-') {
      _pos++;
      final v = _unary();
      return _Num(-v.value, v.currency);
    }
    if (_peekSymbol == '+') {
      _pos++;
      return _unary();
    }
    return _primary();
  }

  _Num _primary() {
    final t = _peek;
    if (t == null) throw _FormulaError('#ERROR!');
    _pos++;
    if (t.group(1) != null) return _Num(double.parse(t.group(1)!), false);
    if (t.group(2) != null) {
      if (t.group(3) != null) throw _FormulaError('#ERROR!'); // bare range
      return _cellNumber(t.group(2)!);
    }
    if (t.group(4) != null) return _function(t.group(4)!.toUpperCase());
    if (t.group(5) == '(') {
      final v = _expression();
      _expect(')');
      return v;
    }
    throw _FormulaError('#ERROR!');
  }

  void _expect(String symbol) {
    if (_peekSymbol != symbol) throw _FormulaError('#ERROR!');
    _pos++;
  }

  (int, int) _ref(String ref) {
    final m = _refPattern.firstMatch(ref)!;
    return (int.parse(m.group(2)!) - 1, _columnIndex(m.group(1)!.toUpperCase()));
  }

  _Num _cellNumber(String ref) {
    final (r, c) = _ref(ref);
    final v = sheet.valueAt(r, c);
    if (v.error != null) throw _FormulaError(v.error!);
    return _Num(v.number ?? 0, v.currency);
  }

  _Num _function(String name) {
    _expect('(');
    final values = <_Num>[];
    if (_peekSymbol != ')') {
      while (true) {
        final t = _peek;
        if (t != null && t.group(2) != null && t.group(3) != null) {
          _pos++;
          values.addAll(_range(t.group(2)!, t.group(3)!));
        } else {
          values.add(_expression());
        }
        if (_peekSymbol == ',' || _peekSymbol == ';') {
          _pos++;
          continue;
        }
        break;
      }
    }
    _expect(')');
    final currency = values.any((v) => v.currency);
    final nums = values.map((v) => v.value).toList();
    switch (name) {
      case 'SUM':
        return _Num(nums.fold(0.0, (a, b) => a + b), currency);
      case 'AVG':
      case 'AVERAGE':
        if (nums.isEmpty) throw _FormulaError('#DIV/0!');
        return _Num(nums.fold(0.0, (a, b) => a + b) / nums.length, currency);
      case 'MIN':
        return _Num(nums.isEmpty ? 0 : nums.reduce(math.min), currency);
      case 'MAX':
        return _Num(nums.isEmpty ? 0 : nums.reduce(math.max), currency);
      case 'COUNT':
        return _Num(nums.length.toDouble(), false);
      default:
        throw _FormulaError('#NAME?');
    }
  }

  /// Numeric cells in a rectangular range; blanks and text are skipped.
  List<_Num> _range(String from, String to) {
    final (r1, c1) = _ref(from);
    final (r2, c2) = _ref(to);
    final out = <_Num>[];
    for (var r = math.min(r1, r2); r <= math.max(r1, r2); r++) {
      for (var c = math.min(c1, c2); c <= math.max(c1, c2); c++) {
        final v = sheet.valueAt(r, c);
        if (v.error != null) throw _FormulaError(v.error!);
        if (v.number != null) out.add(_Num(v.number!, v.currency));
      }
    }
    return out;
  }
}
