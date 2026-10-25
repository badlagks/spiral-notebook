import 'package:flutter/material.dart';

import '../../logic/formula.dart';
import '../../models/notebook.dart';
import '../store_scope.dart';

/// A little spreadsheet taped onto the page, with a formula bar on top.
class SheetView extends StatefulWidget {
  const SheetView({super.key, required this.block});

  final SheetBlock block;

  @override
  State<SheetView> createState() => _SheetViewState();
}

class _SheetViewState extends State<SheetView> {
  static const _cellWidth = 78.0;
  static const _firstColumnWidth = 112.0; // room for item names
  static double _widthOf(int col) => col == 0 ? _firstColumnWidth : _cellWidth;
  static const _rowHeaderWidth = 28.0;
  static const _cellHeight = 24.0;
  static const _border = Color(0xFFC9CED6);
  static const _headerFill = Color(0xFFEFF1F4);
  static const _selected = Color(0xFF2F6FDE);
  static const _uiText = TextStyle(fontFamily: 'Roboto', fontSize: 12.5, color: Color(0xFF222222));

  int _row = 0;
  int _col = 0;
  final _formula = TextEditingController();
  final _formulaFocus = FocusNode();

  SheetBlock get _sheet => widget.block;

  @override
  void initState() {
    super.initState();
    _formula.text = _raw;
  }

  String get _raw =>
      _row < _sheet.rows && _col < _sheet.cols ? _sheet.cells[_row][_col] : '';

  void _select(int row, int col, {bool focus = true}) {
    setState(() {
      _row = row.clamp(0, _sheet.rows - 1);
      _col = col.clamp(0, _sheet.cols - 1);
      _formula.text = _raw;
      _formula.selection = TextSelection.collapsed(offset: _formula.text.length);
    });
    if (focus) _formulaFocus.requestFocus();
  }

  void _edit(String text) {
    setState(() => _sheet.cells[_row][_col] = text);
    StoreScope.read(context).changedQuietly();
  }

  void _resize(VoidCallback change) {
    setState(change);
    _select(_row, _col, focus: false);
    StoreScope.read(context).changed();
  }

  @override
  void dispose() {
    _formula.dispose();
    _formulaFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eval = SheetEvaluator(_sheet.cells);
    final width = _rowHeaderWidth + List.generate(_sheet.cols, _widthOf).fold(0.0, (a, b) => a + b);

    // Drawn at its natural size; the page scales it to the width it was given.
    return Container(
          width: width + 2,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFB5BBC4)),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(1, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _formulaBar(width),
              _headerRow(),
              for (var r = 0; r < _sheet.rows; r++) _dataRow(r, eval),
            ],
          ),
        );
  }

  Widget _formulaBar(double width) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FA),
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _border),
            ),
            child: Text('${columnName(_col)}${_row + 1}', style: _uiText),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text('fx', style: TextStyle(fontFamily: 'Roboto', fontStyle: FontStyle.italic, fontSize: 13, color: Color(0xFF666666))),
          ),
          Expanded(
            child: TextField(
              controller: _formula,
              focusNode: _formulaFocus,
              style: _uiText,
              decoration: const InputDecoration.collapsed(hintText: 'Value or =SUM(A1:A3)'),
              onChanged: _edit,
              onSubmitted: (_) => _select(_row + 1, _col),
            ),
          ),
          _tinyButton(Icons.table_rows_outlined, 'Add row', () => _resize(_sheet.addRow)),
          _tinyButton(Icons.view_column_outlined, 'Add column', () => _resize(_sheet.addColumn)),
          _tinyButton(Icons.remove, 'Remove last row', () => _resize(_sheet.removeRow)),
          _tinyButton(Icons.keyboard_tab_rounded, 'Remove last column', () => _resize(_sheet.removeColumn)),
        ],
      ),
    );
  }

  Widget _tinyButton(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(icon, size: 15, color: const Color(0xFF555555)),
          ),
        ),
      );

  Widget _headerRow() {
    return Row(
      children: [
        _headerCell('', _rowHeaderWidth),
        for (var c = 0; c < _sheet.cols; c++)
          _headerCell(columnName(c), _widthOf(c), active: c == _col),
      ],
    );
  }

  Widget _headerCell(String text, double width, {bool active = false}) => Container(
        width: width,
        height: _cellHeight - 2,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFDDE6F5) : _headerFill,
          border: const Border(
            right: BorderSide(color: _border),
            bottom: BorderSide(color: _border),
          ),
        ),
        child: Text(text, style: _uiText.copyWith(color: const Color(0xFF555555), fontSize: 11.5)),
      );

  Widget _dataRow(int r, SheetEvaluator eval) {
    return Row(
      children: [
        _headerCell('${r + 1}', _rowHeaderWidth, active: r == _row),
        for (var c = 0; c < _sheet.cols; c++) _cell(r, c, eval.valueAt(r, c)),
      ],
    );
  }

  Widget _cell(int r, int c, CellValue value) {
    final selected = r == _row && c == _col;
    final isFormula = _sheet.cells[r][c].trim().startsWith('=');
    final header = r == 0 && value.number == null && value.text!.isNotEmpty;
    return GestureDetector(
      onTap: () => _select(r, c),
      child: Container(
        width: _widthOf(c),
        height: _cellHeight,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: value.number != null ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: isFormula ? const Color(0xFFFFF6D6) : null,
          border: selected
              ? Border.all(color: _selected, width: 2)
              : const Border(
                  right: BorderSide(color: _border),
                  bottom: BorderSide(color: _border),
                ),
        ),
        child: Text(
          value.display,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
          style: _uiText.copyWith(
            fontWeight: header ? FontWeight.w600 : null,
            color: value.error != null ? const Color(0xFFC0392B) : null,
          ),
        ),
      ),
    );
  }
}
