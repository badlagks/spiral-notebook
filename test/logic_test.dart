import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spiral_notebook/data/sample_notebook.dart';
import 'package:spiral_notebook/logic/calculator.dart';
import 'package:spiral_notebook/logic/formula.dart';
import 'package:spiral_notebook/models/notebook.dart';
import 'package:spiral_notebook/ui/blocks/text_block_view.dart';

String eval(List<List<String>> cells, int r, int c) => SheetEvaluator(cells).valueAt(r, c).display;

void main() {
  group('spreadsheet formulas', () {
    test('arithmetic and precedence', () {
      expect(eval([['=1+2*3']], 0, 0), '7');
      expect(eval([['=(1+2)*3']], 0, 0), '9');
      expect(eval([['=2^3^2']], 0, 0), '512');
      expect(eval([['=-4+10/4']], 0, 0), '-1.5');
    });

    test('cell references and currency', () {
      final cells = [
        ['Qty', 'Price', 'Total'],
        ['2', '\$10.00', '=A2*B2'],
        ['3', '\$1.50', '=A3*B3'],
        ['', '', '=SUM(C2:C3)'],
      ];
      expect(eval(cells, 1, 2), '\$20.00');
      expect(eval(cells, 3, 2), '\$24.50');
    });

    test('functions skip text and blanks', () {
      final cells = [
        ['a', '4', '', '6', '=AVG(A1:D1)', '=COUNT(A1:D1)', '=MAX(A1:D1)', '=MIN(B1,D1,1)'],
      ];
      expect(eval(cells, 0, 4), '5');
      expect(eval(cells, 0, 5), '2');
      expect(eval(cells, 0, 6), '6');
      expect(eval(cells, 0, 7), '1');
    });

    test('errors', () {
      expect(eval([['=A1']], 0, 0), '#CYCLE!');
      expect(eval([['=1/0']], 0, 0), '#DIV/0!');
      expect(eval([['=FOO(1)']], 0, 0), '#NAME?');
      expect(eval([['=1+']], 0, 0), '#ERROR!');
      expect(eval([['=1/0', '=A1+1']], 0, 1), '#DIV/0!');
    });

    test('loose numbers and formatting', () {
      expect(parseLooseNumber('1,450.00'), 1450);
      expect(parseLooseNumber('\$5'), 5);
      expect(parseLooseNumber('abc'), isNull);
      expect(formatNumber(1234567.5), '1,234,567.5');
      expect(formatNumber(-50, currency: true), '-\$50.00');
      expect(columnName(0), 'A');
      expect(columnName(27), 'AB');
    });

    test('sample sheet totals', () {
      final sheet = sampleNotebook().sections.first.pages.first.blocks.whereType<SheetBlock>().first;
      expect(eval(sheet.cells, 5, 3), '\$16.00');
    });
  });

  group('calculator', () {
    CalculatorEngine press(String keys) {
      final c = CalculatorEngine();
      for (final k in keys.split(' ')) {
        c.press(k);
      }
      return c;
    }

    test('chains like a desk calculator', () {
      expect(press('1 2 + 3 × 2 =').display, '30');
      expect(press('1 0 ÷ 4 =').display, '2.5');
      expect(press('0 . 1 + 0 . 2 =').display, '0.3');
      expect(press('1 4 5 0 . 0 0').display, '1,450.00');
    });

    test('percent, root, sign and errors', () {
      expect(press('2 0 0 + 1 0 % =').display, '220');
      expect(press('8 1 √').display, '9');
      expect(press('5 ±').display, '-5');
      expect(press('5 ÷ 0 =').display, 'Error');
      expect(press('5 ÷ 0 = C').display, '0');
    });

    test('memory', () {
      final c = press('4 M+ 6 M+ C MR');
      expect(c.display, '10');
      expect(c.memory, 10);
    });

    test('restores a saved display', () {
      expect(CalculatorEngine(display: '1,450.00').display, '1,450.00');
    });
  });

  group('outline typing', () {
    TextEditingValue type(String before, String after) => OutlineContinuationFormatter().formatEditUpdate(
          TextEditingValue(text: before, selection: TextSelection.collapsed(offset: before.length)),
          TextEditingValue(text: after, selection: TextSelection.collapsed(offset: after.length)),
        );

    test('continues a bullet at the same indent', () {
      final v = type('  - Plan', '  - Plan\n');
      expect(v.text, '  - Plan\n  - ');
      expect(v.selection.baseOffset, v.text.length);
    });

    test('Enter on an empty bullet ends the outline', () {
      expect(type('- a\n- ', '- a\n- \n').text, '- a\n');
    });

    test('plain lines are untouched', () {
      expect(type('hello', 'hello\n').text, 'hello\n');
    });
  });

  test('notebook survives a save and load', () {
    final nb = sampleNotebook();
    final copy = Notebook.fromJson(jsonDecode(jsonEncode(nb.toJson())) as Map<String, dynamic>);
    expect(jsonEncode(copy.toJson()), jsonEncode(nb.toJson()));
    expect(copy.sections.map((s) => s.name), ['Ideas', 'Daily', 'Finances', 'Tasks']);
    final blocks = copy.sections.first.pages[1].blocks;
    expect(blocks.whereType<ChecklistBlock>().first.items.where((i) => i.done).length, 4);
    expect(blocks.whereType<CalculatorBlock>().first.display, '1,450.00');
  });
}
